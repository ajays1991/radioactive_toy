require "aws-sdk-rds"

module RadioactiveToy
	class RdsProvisioner
		attr_reader :ec_rds, :environment, :rds_secret, :vpc_security_group_ids, :rds_config, :private_subnet_ids, :db_subnet_group_name

		def initialize(region:, rds_config:, environment:, rds_secret:, vpc_security_group_ids:, private_subnet_ids:)
			@ec_rds = Aws::RDS::Client.new(
			  region: region)
			@rds_config = rds_config
			@rds_secret = rds_secret
			@environment = environment
			@vpc_security_group_ids = vpc_security_group_ids
			@private_subnet_ids = private_subnet_ids
			@db_subnet_group_name = "#{environment}-db-subnet-group-rails-terraform-2_#{Time.now.strftime("%Y%m%d%H%M%S")}"
		end

		def create
			begin
				rds_username = rds_secret.find { |sec| sec.key?(:RDS_USERNAME) }[:RDS_USERNAME]
				rds_password = rds_secret.find { |sec| sec.key?(:RDS_PASSWORD) }[:RDS_PASSWORD]
				create_subnet
			  response = ec_rds.create_db_instance(
				  db_instance_identifier: rds_config["identifier"],
				  allocated_storage: rds_config["storage"],
				   storage_type: "gp3",
				  db_instance_class: rds_config["instance_class"],
				  engine: rds_config["engine"],
				  engine_version: rds_config["engine_version"].to_s,
				  master_username: rds_username,
				  master_user_password: rds_password,
				  db_name: rds_config["db_name"],
				  db_subnet_group_name: db_subnet_group_name,
				  vpc_security_group_ids: [vpc_security_group_ids]
				)

			  puts "RDS creation started"
			  puts response
			  puts response.db_instance.db_instance_identifier
			  response
			rescue Aws::RDS::Errors::ServiceError => e
			  puts "Error: #{e.message}"
			end
		end

		private
		def create_subnet
			begin
				ec_rds.create_db_subnet_group(
				  db_subnet_group_name: db_subnet_group_name,
				  db_subnet_group_description: "#{environment} db subnet group",
				  subnet_ids: private_subnet_ids
				)
			rescue StandardError => e
				puts "-------------------------RDS error #{e.message}"
			end
		end
	end
end