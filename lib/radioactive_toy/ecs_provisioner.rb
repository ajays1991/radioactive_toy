require "aws-sdk-ecs"
require 'aws-sdk-applicationautoscaling'

module RadioactiveToy
	class EcsProvisioner
		attr_reader :ecs, :autoscaling, :image_uri, :env_variables, :task_definition_arn, :vpc_security_group_ids, :private_subnet_ids, :task_definition_arn, :ecs_config, :ecs_environment

		def initialize(region:, ecs_config:, image_uri:, env_variables:, vpc_security_group_ids:, private_subnet_ids:)
			@ecs = Aws::ECS::Client.new(
			  region: region
			)
			@autoscaling = Aws::ApplicationAutoScaling::Client.new(
			  region: region
			)
			@image_uri = image_uri
			@env_variables = env_variables
			@vpc_security_group_ids = vpc_security_group_ids
			@ecs_config = ecs_config
			@private_subnet_ids = private_subnet_ids
			@ecs_environment =
			  env_variables.flat_map do |hash|
			    hash.map do |key, value|
			      {
			        name: key.to_s,
			        value: value.to_s
			      }
			    end
			  end
		end

		def create
			create_cluster
			register_task_definition
			create_ecs_service
			create_auto_scalling
		end

		private

		def create_cluster
			response = ecs.create_cluster(
			  cluster_name: ecs_config["cluster_name"]
			)

			puts "Cluster ARN: #{response.cluster.cluster_arn}"
			response.cluster.cluster_arn
		end

		def register_task_definition
			binding.break
			response = ecs.register_task_definition(
			  family: ecs_config["family_name"],
			  network_mode: 'awsvpc',
			  requires_compatibilities: ['FARGATE'],
			  cpu: ecs_config["cpu"].to_s,
			  memory: ecs_config["memory"].to_s,
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
			      environment: ecs_environment
			    }
			  ]
			)
			binding.break
			@task_definition_arn = response.task_definition.task_definition_arn

			puts @task_definition_arn
		end

		def create_ecs_service
			binding.break
			response = ecs.create_service(
			  cluster: ecs_config["cluster_name"],
			  service_name: ecs_config["service_name"],
			  task_definition: task_definition_arn,
			  desired_count: 1,
			  launch_type: 'FARGATE',
			  network_configuration: {
			    awsvpc_configuration: {
			      subnets: private_subnet_ids,
			      security_groups: [vpc_security_group_ids],
			      assign_public_ip: 'ENABLED'
			    }
			  }
			)

			puts response.service.service_arn
		end

		def create_auto_scalling

			resource_id = "service/#{ecs_config["cluster_name"]}/#{ecs_config["service_name"]}"

			autoscaling.register_scalable_target(
			  service_namespace: 'ecs',
			  resource_id: resource_id,
			  scalable_dimension: 'ecs:service:DesiredCount',
			  min_capacity: ecs_config["min_capacity"],
			  max_capacity: ecs_config["max_capacity"]
			)

			autoscaling.put_scaling_policy(
			  policy_name: "#{service_name}-cpu-scaling",
			  service_namespace: 'ecs',
			  resource_id: resource_id,
			  scalable_dimension: 'ecs:service:DesiredCount',
			  policy_type: 'TargetTrackingScaling',
			  target_tracking_scaling_policy_configuration: {
			    target_value: ecs_config["cpu_target_value"],
			    predefined_metric_specification: {
			      predefined_metric_type: 'ECSServiceAverageCPUUtilization'
			    },
			    scale_in_cooldown: ecs_config["cpu_scale_in_cooldown"],
			    scale_out_cooldown: ecs_config["cpu_scale_out_cooldown"]
			  }
			)

			autoscaling.put_scaling_policy(
			  policy_name: "#{ecs_config["service_name"]}-memory-scaling",
			  service_namespace: 'ecs',
			  resource_id: resource_id,
			  scalable_dimension: 'ecs:service:DesiredCount',
			  policy_type: 'TargetTrackingScaling',
			  target_tracking_scaling_policy_configuration: {
			    target_value: ecs_config["memory_target_value"],
			    predefined_metric_specification: {
			      predefined_metric_type: 'ECSServiceAverageMemoryUtilization'
			    },
			    scale_in_cooldown: ecs_config["memory_scale_in_cooldown"],
			    scale_out_cooldown: ecs_config["memory_scale_out_cooldown"]
			  }
			)
		end
	end
end