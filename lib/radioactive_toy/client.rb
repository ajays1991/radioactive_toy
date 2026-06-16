require "aws-sdk-ecr"
require "aws-sdk-secretsmanager"
require "yaml"

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

      # set tfvarsa for container definition through terraform, not using env with docker build

      # config['deployment']['terraform_variables'].each do |var|
      #   value = @client.get_secret_value(secret_id: var).secret_string
      #   ENV["TF_VAR_#{var}"] = value
      # end 

      ##code to read ruby version from .ruby_version
      repository_name = config["provider"]["repository_name"]
      aws_account_id = config["provider"]["aws_account_id"]
      aws_region = config["provider"]["aws_region"]
      image_tag = config["infra_config"]["image_tag"] || "latest"
      ecr_uri = "#{aws_account_id}.dkr.ecr.#{aws_region}.amazonaws.com/#{repository_name}"
      image_uri = "#{ecr_uri}:#{image_tag}"

      puts repository_name
      # var_hash = generate_secret_hash

      ruby_version_file = Rails.root.join(".ruby-version")

      ruby_version = File.read(ruby_version_file).strip

      puts ruby_version

      # ecr client to fetch all repositories

      @client = Aws::ECR::Client.new(
          region: "ap-south-1"
        )
      puts @client.describe_repositories.repositories

      # code to fetch all the secrets along with secret value from aws secret manager

      client = Aws::SecretsManager::Client.new(
        region: "ap-south-1"
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
      #build_image(repository_name:repository_name, image_tag: "latest", ruby_version: ruby_version)
      #login_to_ecr(aws_account_id: aws_account_id, aws_region: aws_region)
      create_ecr_repository(repository_name: repository_name, aws_region: aws_region)
      tag_image(repository_name: repository_name, image_tag: image_tag, image_uri: image_uri)
      login_to_ecr(aws_account_id: aws_account_id, aws_region: aws_region)
      push_image(image_uri: image_uri)
      network = RadioactiveToy::NetworkProvisioner.new(
        region: "ap-south-1"
      )

      result = network.create_network(
        environment: "prod",
        vpc_cidr: "10.0.0.0/16",
        public_subnets_cidr: [
          "10.0.1.0/24",
          "10.0.2.0/24"
        ],
        private_subnets_cidr: [
          "10.0.11.0/24",
          "10.0.12.0/24"
        ],
        availability_zones: [
          "ap-south-1a",
          "ap-south-1b"
        ]
      )
      puts "---------------------------Network #{result}"
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

    # ruby system line command execution to build docker, passing ruby version, environment variables as build args


    # upload built docker image to ECR and retrieve ECS task definition

    # aws sdk code to check if RDS exist


    # aws sdk to check if elasticcache exist
    # for both they will be used to pass as arugements to terraform apply if resource needs to be created or not

      
  end
end