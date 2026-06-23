require 'kubeclient'
require 'aws-sdk-eks'

module RadioactiveToy
  class EksProvisioner
    attr_reader :eks, :autoscaling, :cluster_name, :image_uri, :cpu, :memory, :family, :env_variables, :task_definition_arn, :security_groups, :subnets, :config :service_name

    def initialize(region:, eks_config:, cluster_name:, family:, image_uri:, cpu:, memory:, env_variables:, security_groups:,)
      @eks = Aws::EKS::Client.new(
        region: region
      )
      @autoscaling = Aws::ApplicationAutoScaling::Client.new(
        region: region
      )
      @eks_config = eks_config
      @cluster_name = cluster_name
      @image_uri = image_uri
      @cpu = cpu
      @memory = memory
      @family = family
      @env_variables = env_variables
      @security_groups = security_groups
      @subnets = subnets
      @service_name = service_name
    end

    def run
      create_cluster
      register_task_definition
      create_ecs_service
      create_auto_scalling
    end

    private

    def create_cluster
      response = eks.create_cluster(
        name: 'rails-cluster',
        version: '1.33',
        role_arn: 'arn:aws:iam::824140446440:role/EKSClusterRole',
        resources_vpc_config: {
          subnet_ids: [
            'subnet-123456',
            'subnet-789012'
          ],
          security_group_ids: [
            'sg-123456'
          ],
          endpoint_public_access: true
        }
      )

      loop do
        cluster = eks.describe_cluster(
          name: 'rails-cluster'
        ).cluster

        break if cluster.status == 'ACTIVE'

        puts "Waiting..."
        sleep 30
      end

      puts response.cluster.arn

      response = eks.create_nodegroup(
        cluster_name: 'rails-cluster',
        subnets: subnets,
        nodegroup_name: 'rails-nodes',
        node_role: 'arn:aws:iam::824140446440:role/EKSNodeGroupRole',
        scaling_config: {
          min_size: 2,
          max_size: 10,
          desired_size: 2
        },
        instance_types: [
          't3.medium'
        ],
        ami_type: 'AL2023_x86_64_STANDARD',
        capacity_type: 'ON_DEMAND'
      )

      puts response.nodegroup.nodegroup_arn
    endcluster_name: 'rails-cluster',
        nodegroup_name: 'rails-nodes',
        node_role: 'arn:aws:iam::824140446440:role/EKSNodeGroupRole',
        subnets: [
          'subnet-123456',
          'subnet-789012'
        ],
        scaling_config: {
          min_size: 2,
          max_size: 10,
          desired_size: 2
        },
        instance_types: [
          't3.medium'
        ],
        ami_type: 'AL2023_x86_64_STANDARD',
        capacity_type: 'ON_DEMAND'
      )

      puts response.nodegroup.nodegroup_arn

    def register_task_definition
      response = ecs.register_task_definition(
        family: 'my-app',
        network_mode: 'awsvpc',
        requires_compatibilities: ['FARGATE'],
        cpu: cpu,
        memory: memory,
        execution_role_arn: 'arn:aws:iam::824140446440:role/ecsTaskExecutionRole',
        container_definitions: [
          {
            name: 'web',
            image: image_uri,
            essential: true,
            port_mappings: [
              {
                container_port: 3000,
                protocol: 'tcp'
              }
            ],
            environment: env_variables
          }
        ]
      )

      @task_definition_arn = response.task_definition.task_definition_arn

      puts @task_definition_arn
    end

    def create_ecs_service
      response = ecs.create_service(
        cluster: cluster_name,
        service_name: service_name,
        task_definition: task_definition_arn,
        desired_count: 1,
        launch_type: 'FARGATE',
        network_configuration: {
          awsvpc_configuration: {
            subnets: [
              'subnet-abc123',
              'subnet-def456'
            ],
            security_groups: security_groups,
            assign_public_ip: 'ENABLED'
          }
        }
      )

      puts response.service.service_arn
    end

    def create_auto_scalling

      resource_id = "service/#{cluster_name}/#{service_name}",

      autoscaling.register_scalable_target(
        service_namespace: 'ecs',
        resource_id: resource_id,
        scalable_dimension: 'ecs:service:DesiredCount',
        min_capacity: min_capacity,
        max_capacity: max_capacity
      )

      autoscaling.put_scaling_policy(
        policy_name: "#{service_name}-cpu-scaling",
        service_namespace: 'ecs',
        resource_id: resource_id,
        scalable_dimension: 'ecs:service:DesiredCount',
        policy_type: 'TargetTrackingScaling',
        target_tracking_scaling_policy_configuration: {
          target_value: cpu_target_value,
          predefined_metric_specification: {
            predefined_metric_type: 'ECSServiceAverageCPUUtilization'
          },
          scale_in_cooldown: cpu_scale_in_cooldown,
          scale_out_cooldown: cpu_scale_out_cooldown
        }
      )

      autoscaling.put_scaling_policy(
        policy_name: "#{service_name}-memory-scaling",
        service_namespace: 'ecs',
        resource_id: "service/#{cluster_name}/#{service_name}",
        scalable_dimension: 'ecs:service:DesiredCount',
        policy_type: 'TargetTrackingScaling',
        target_tracking_scaling_policy_configuration: {
          target_value: memory_target_value,
          predefined_metric_specification: {
            predefined_metric_type: 'ECSServiceAverageMemoryUtilization'
          },
          scale_in_cooldown: memory_scale_in_cooldown,
          scale_out_cooldown: memory_scale_out_cooldown
        }
      )
    end
  end
end