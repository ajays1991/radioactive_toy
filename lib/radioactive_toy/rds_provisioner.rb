require "aws-sdk-rds"

module RadioactiveToy
	class RdsProvisioner
		attr_reader :ec_rds

		def initialize(region:, rds_config:, rds_secret:)
			@ec_rds = Aws::RDS::Client.new(
			  region: region)
			@rds_config = rds_config
		end

		def run
			begin
			  response = rds.create_db_instance(
			    db_instance_identifier: 'my-rails-db',
			    allocated_storage: rds_config["allocated_storage"],
			    db_instance_class: 'db.t3.micro',
			    engine: 'postgres',
			    engine_version: '15.4',
			    master_username: 'postgres',
			    master_user_password: 'YourStrongPassword123!',
			    db_name: 'myapp',
			    publicly_accessible: false,
			    storage_type: 'gp3',
			    backup_retention_period: 7,
			    multi_az: false,
			    auto_minor_version_upgrade: true,
			    deletion_protection: false,
			    storage_encrypted: true
			  )

			  puts "RDS creation started"
			  puts response.db_instance.db_instance_identifier

			rescue Aws::RDS::Errors::ServiceError => e
			  puts "Error: #{e.message}"
			end
		end

		private
	end
end