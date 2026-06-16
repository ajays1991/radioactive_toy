require 'kubeclient'
require 'aws-sdk-eks'

module RadioactiveToy
  class EksProvisioner
    attr_reader :ecs, :autoscaling, :cluster_name, :image_uri, :cpu, :memory, :family, :env_variables, :task_definition_arn, :security_groups, :subnets, :service_name

    def initialize(region:, cluster_name:, family:, image_uri:, cpu:, memory:, env_variables:, security_groups:,)
      @ecs = Aws::ECS::Client.new(
        region: region
      )
      @autoscaling = Aws::ApplicationAutoScaling::Client.new(
        region: region
      )
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
      response = ecs.create_cluster(
        cluster_name: cluster_name
      )

      puts "Cluster ARN: #{response.cluster.cluster_arn}"
      response.cluster.cluster_arn
    end

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