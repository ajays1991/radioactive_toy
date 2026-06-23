require "aws-sdk-ecr"
require "aws-sdk-secretsmanager"
require "yaml"
require "aws-sdk-ec2"

module RadioactiveToy
  class Client
    def deploy

      # code to set AWS_API_KEY, AWS_SECRET and Github token from github actions secrets, TOBD if encrypted values from config,json

      #ENV["AWS_ACCESS_KEY_ID"] = "xxx"

      system("mkdir test1")
      system("cd test")
      system("echo ajay")

      # code to read radioactive_toy.json

      puts "--------------------putting byebug----------------"
      binding.break
      puts "Deploying application..."
      config_file = Rails.root.join("config", "radioactive_toy.yml")

      raise "Config file not found: #{config_file}" unless File.exist?(config_file)

      config = YAML.safe_load(
        File.read(config_file),
        aliases: true
      )

      @config = config.transform_keys(&:to_sym)

      puts config["provider"]["repository_name"]

      #set tfvarsa for container definition through terraform, not using env with docker build

      ##code to read ruby version from .ruby_version
      repository_name = config["provider"]["repository_name"]
      aws_account_id = config["provider"]["aws_account_id"]
      aws_region = config["provider"]["aws_region"]
      image_tag = config["infra_config"]["image_tag"] || "latest"
      ecr_uri = "#{aws_account_id}.dkr.ecr.#{aws_region}.amazonaws.com/#{repository_name}"
      image_uri = "#{ecr_uri}:#{image_tag}"
      secrets_from_config = config["infra_secrets"]

      network_config = config["infra_config"]["network"]
      rds_config = config["infra_config"]["rds"]
      ecs_config = config["infra_config"]["ecs"]
      elastic_cache_config = config["infra_config"]["elastic_cache"]
      puts repository_name
      # var_hash = generate_secret_hash

      ruby_version_file = Rails.root.join(".ruby-version")

      ruby_version = File.read(ruby_version_file).strip

      puts ruby_version

      # ecr client to fetch all repositories

      @client = Aws::ECR::Client.new(
          region: aws_region
        )
      puts @client.describe_repositories.repositories

      # code to fetch all the secrets along with secret value from aws secret manager

      client = Aws::SecretsManager::Client.new(
        region: aws_region
      )

      secrets = []

      next_token = nil


      loop do
        response = client.list_secrets(
          next_token: next_token,
          max_results: 100
        )

        response.secret_list.each do |secret|
          begin
            value_response = client.get_secret_value(
              secret_id: secret.name
            )

            secrets << {
              name: secret.name,
              arn: secret.arn,
              value: value_response.secret_string
            }
          rescue Aws::SecretsManager::Errors::AccessDeniedException => e
            puts "Access denied for #{secret.name}: #{e.message}"
          rescue StandardError => e
            puts "Error reading #{secret.name}: #{e.message}"
          end
        end

        next_token = response.next_token
        break unless next_token
      end
      # fetch a secret
      puts secrets

      mapped_secrets = secrets.map do |secret|
        parsed_value = JSON.parse(secret[:value])
        next unless secrets_from_config.include?(parsed_value.keys.first)
        {
          parsed_value.keys.first.to_sym => parsed_value.values.first
        }
      end
      
      #build_image(repository_name:repository_name, image_tag: "latest", ruby_version: ruby_version)
      login_to_ecr(aws_account_id: aws_account_id, aws_region: aws_region)
      create_ecr_repository(repository_name: repository_name, aws_region: aws_region)
      tag_image(repository_name: repository_name, image_tag: image_tag, image_uri: image_uri)
      login_to_ecr(aws_account_id: aws_account_id, aws_region: aws_region)
      push_image(image_uri: image_uri)
      ecs_network = RadioactiveToy::NetworkProvisioner.new(
        environment: "prod",
        network_config: network_config,
        region: aws_region
      )

      ecs_network_result = ecs_network.create_network
      puts "---------------------------Network #{ecs_network_result}" 
      # delete_vpc
      # return "x"

      ##create RDS
      rds = RadioactiveToy::RdsProvisioner.new(region: aws_region, rds_config: rds_config, rds_secret: mapped_secrets, environment: "prod", vpc_security_group_ids: ecs_network_result[:security_group_id], private_subnet_ids: ecs_network_result[:private_subnet_ids])
      rds_result = rds.create

      

      # puts "----------------------------RDS #{rds_result}"

      ##create ecs
      ecs_result = RadioactiveToy::EcsProvisioner.new(region: aws_region, ecs_config: ecs_config, image_uri: image_uri, env_variables: mapped_secrets, vpc_security_group_ids: ecs_network_result[:security_group_id], private_subnet_ids: ecs_network_result[:private_subnet_ids])
      ecs_result.create
       puts "****************************************************** ECS #{ecs_result}"
    end

    def create_ecr_repository(repository_name:, aws_region:)
      ecr = Aws::ECR::Client.new(region: aws_region)

      begin
        ecr.describe_repositories(
          repository_names: [repository_name]
        )

        puts "Repository #{repository_name} already exists"
      rescue Aws::ECR::Errors::RepositoryNotFoundException
        ecr.create_repository(
          repository_name: repository_name
        )

        puts "Repository #{repository_name} created"
      end
    end

    # def create_ecr_repository(repository_name:, aws_region:)
    #   run!(<<~CMD)
    #     aws ecr describe-repositories \
    #     --repository-names #{repository_name} \
    #     --region #{aws_region} \
    #     >/dev/null 2>&1 || \
    #     aws ecr create-repository \
    #     --repository-name #{repository_name} \
    #     --region #{aws_region}
    #   CMD
    # end

    def build_image(repository_name:, image_tag:, ruby_version:)
        puts "repository_name=#{repository_name.inspect}"
        puts "image_tag=#{image_tag.inspect}"
        puts "ruby_version=#{ruby_version.inspect}"
        puts "dockerfile=#{dockerfile.inspect}"
      run!(<<~CMD)
        docker build \
          -f #{dockerfile} \
          -t #{repository_name}:#{image_tag} \
          --build-arg RUBY_VERSION=#{ruby_version} \
          .
      CMD
    end

    def login_to_ecr(aws_account_id:, aws_region:)
      run!(<<~CMD)
        aws ecr get-login-password \
        --region #{aws_region} | \
        docker login \
        --username AWS \
        --password-stdin \
        #{aws_account_id}.dkr.ecr.#{aws_region}.amazonaws.com
      CMD
    end

    def tag_image(repository_name:, image_tag:, image_uri:)
      run!(<<~CMD)
        docker tag \
        #{repository_name}:#{image_tag} \
        #{image_uri}
      CMD
    end

    def push_image(image_uri:)
      run!(<<~CMD)
        docker push #{image_uri}
      CMD
    end

    def run!(cmd)
      puts "Running: #{cmd}"

      success = system(cmd)

      raise "Command failed: #{cmd}" unless success
    end

    def output_terraform_values(vars)
      terraform_output = vars

      puts "\nTerraform Variables:"
      puts JSON.pretty_generate(terraform_output)

      File.write(
        "terraform.auto.tfvars.json",
        JSON.pretty_generate(terraform_output)
      )
    end

    def dockerfile
      Rails.root.join("Dockerfile")
    end

    # def image_tag
    #   @config["infra_config"]["image_tag"]
    # end

    def generate_secret_hash(secrets)
      result = {}
      secrets.each do |key, value|
        result[key.to_sym] = value
      end
      result
    end

    # build argument string for docker build for secrets and values

    docker_build_args = ""

    docker_build_command = ""

    system(docker_build_command)

    def delete_vpc
      ec2 = Aws::EC2::Client.new(
        region: "ap-southeast-1"
      )

      response = ec2.describe_vpcs

      vpc_ids = response.vpcs.map(&:vpc_id)

      puts vpc_ids
      vpc_ids.each do |vpc_id|
        delete_nat_gateways(ec2, vpc_id)
        delete_security_groups(ec2, vpc_id)
        delete_route_tables(ec2, vpc_id)
        delete_internet_gateways(ec2, vpc_id)
        delete_subnets(ec2, vpc_id)

        ec2.delete_vpc(vpc_id: vpc_id)

        puts "Deleted #{vpc_id}"
      end
      delete_address(ec2)
    end

    def delete_nat_gateways(ec2, vpc_id)
      response = ec2.describe_nat_gateways(
        filter: [
          {
            name: "vpc-id",
            values: [vpc_id]
          }
        ]
      )

      response.nat_gateways.each do |nat|
        ec2.delete_nat_gateway(
          nat_gateway_id: nat.nat_gateway_id
        )

        puts "Deleting NAT #{nat.nat_gateway_id}"

        loop do
          gateway = ec2.describe_nat_gateways(
            nat_gateway_ids: [nat.nat_gateway_id]
          ).nat_gateways.first

          break if gateway.state == "deleted"

          sleep 15
        end

        nat.nat_gateway_addresses.each do |address|
          next unless address.allocation_id

          ec2.release_address(
            allocation_id: address.allocation_id
          )
        end
      end
    end

    def delete_security_groups(ec2, vpc_id)
      groups = ec2.describe_security_groups(
        filters: [
          {
            name: "vpc-id",
            values: [vpc_id]
          }
        ]
      )

      groups.security_groups.each do |sg|
        next if sg.group_name == "default"

        begin
          ec2.delete_security_group(
            group_id: sg.group_id
          )
        rescue => e
          puts e.message
        end
      end
    end

    def delete_route_tables(ec2, vpc_id)
      route_tables = ec2.describe_route_tables(
        filters: [
          {
            name: "vpc-id",
            values: [vpc_id]
          }
        ]
      )

      route_tables.route_tables.each do |rt|
        rt.associations.each do |assoc|
          next if assoc.main

          ec2.disassociate_route_table(
            association_id: assoc.route_table_association_id
          )
        end

        next if rt.associations.any?(&:main)

        begin
          ec2.delete_route_table(
            route_table_id: rt.route_table_id
          )
        rescue => e
          puts e.message
        end
      end
    end

    def delete_internet_gateways(ec2, vpc_id)
      igws = ec2.describe_internet_gateways(
        filters: [
          {
            name: "attachment.vpc-id",
            values: [vpc_id]
          }
        ]
      )

      igws.internet_gateways.each do |igw|
        ec2.detach_internet_gateway(
          internet_gateway_id: igw.internet_gateway_id,
          vpc_id: vpc_id
        )

        ec2.delete_internet_gateway(
          internet_gateway_id: igw.internet_gateway_id
        )
      end
    end

    def delete_subnets(ec2, vpc_id)
      subnets = ec2.describe_subnets(
        filters: [
          {
            name: "vpc-id",
            values: [vpc_id]
          }
        ]
      )

      subnets.subnets.each do |subnet|
        ec2.delete_subnet(
          subnet_id: subnet.subnet_id
        )
      end
    end

    def delete_address(ec2)
      ec2.describe_addresses.addresses.each do |address|
        begin
          if address.association_id
            puts "Disassociating #{address.public_ip}"

            ec2.disassociate_address(
              association_id: address.association_id
            )
          end

          puts "Releasing #{address.public_ip}"

          ec2.release_address(
            allocation_id: address.allocation_id
          )
        rescue => e
          puts "Failed for #{address.public_ip}: #{e.message}"
        end
      end
    end
    # ruby system line command execution to build docker, passing ruby version, environment variables as build args


    # upload built docker image to ECR and retrieve ECS task definition

    # aws sdk code to check if RDS exist


    # aws sdk to check if elasticcache exist
    # for both they will be used to pass as arugements to terraform apply if resource needs to be created or not

      
  end
end