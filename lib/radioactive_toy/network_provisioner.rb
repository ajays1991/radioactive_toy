require "aws-sdk-ec2"

module RadioactiveToy
	class NetworkProvisioner
		attr_reader :ec2, :environment, :network_config

		def initialize( environment:, network_config:, region:)
			@ec2 = Aws::EC2::Client.new(region: region)
			@environment = environment
			@network_config = network_config
		end

		def create_network
			vpc = ec2.create_vpc(
			  cidr_block: network_config["vpc_cidr"]
			)

			vpc_id = vpc.vpc.vpc_id

			ec2.modify_vpc_attribute(
			  vpc_id: vpc_id,
			  enable_dns_support: { value: network_config["enable_dns_support"] }
			)

			ec2.modify_vpc_attribute(
			  vpc_id: vpc_id,
			  enable_dns_hostnames: { value: network_config["enable_dns_hostnames"] }
			)

			tag_resource(vpc_id,
			  "Name" => "#{environment}-vpc",
			  "Environment" => environment
			)

			#
			# Internet Gateway
			#
			igw = ec2.create_internet_gateway
			igw_id = igw.internet_gateway.internet_gateway_id

			ec2.attach_internet_gateway(
			  internet_gateway_id: igw_id,
			  vpc_id: vpc_id
			)

			tag_resource(igw_id,
			  "Name" => "#{environment}-igw",
			  "Environment" => environment
			)

			#
			# Public Subnets
			#
			public_subnet_ids = network_config["public_subnets_cidr"].each_with_index.map do |cidr, index|
			  subnet = ec2.create_subnet(
			    vpc_id: vpc_id,
			    cidr_block: cidr,
			    availability_zone: network_config["availability_zones"][index]
			  )

			  subnet_id = subnet.subnet.subnet_id

			  ec2.modify_subnet_attribute(
			    subnet_id: subnet_id,
			    map_public_ip_on_launch: {
			      value: true
			    }
			  )

			  tag_resource(subnet_id,
			    "Name" => "#{environment}-#{network_config["availability_zones"]}-public-subnet",
			    "Environment" => environment
			  )

			  subnet_id
			end

			#
			# Private Subnets
			#
			private_subnet_ids = network_config["private_subnets_cidr"].each_with_index.map do |cidr, index|
			  subnet = ec2.create_subnet(
			    vpc_id: vpc_id,
			    cidr_block: cidr,
			    availability_zone: network_config["availability_zones"][index]
			  )

			  subnet_id = subnet.subnet.subnet_id

			  tag_resource(subnet_id,
			    "Name" => "#{environment}-#{network_config["availability_zones"][index]}-private-subnet",
			    "Environment" => environment
			  )

			  subnet_id
			end

			#
			# Elastic IP for NAT
			#
			eip = ec2.allocate_address(
			  domain: "vpc"
			)

			allocation_id = eip.allocation_id

			#
			# NAT Gateway
			#
			nat = ec2.create_nat_gateway(
			  allocation_id: allocation_id,
			  subnet_id: public_subnet_ids.first
			)

			nat_gateway_id = nat.nat_gateway.nat_gateway_id

			puts "Waiting for NAT Gateway..."

			wait_for_nat_gateway(nat_gateway_id)

			tag_resource(nat_gateway_id,
			  "Name" => "#{environment}-nat",
			  "Environment" => environment
			)

			#
			# Public Route Table
			#
			public_rt = ec2.create_route_table(
			  vpc_id: vpc_id
			)

			public_rt_id = public_rt.route_table.route_table_id

			tag_resource(public_rt_id,
			  "Name" => "#{environment}-public-route-table",
			  "Environment" => environment
			)

			ec2.create_route(
			  route_table_id: public_rt_id,
			  destination_cidr_block: "0.0.0.0/0",
			  gateway_id: igw_id
			)

			#
			# Private Route Table
			#
			private_rt = ec2.create_route_table(
			  vpc_id: vpc_id
			)

			private_rt_id = private_rt.route_table.route_table_id

			tag_resource(private_rt_id,
			  "Name" => "#{environment}-private-route-table",
			  "Environment" => environment
			)

			ec2.create_route(
			  route_table_id: private_rt_id,
			  destination_cidr_block: "0.0.0.0/0",
			  nat_gateway_id: nat_gateway_id
			)

			#
			# Associate Public Subnets
			#
			public_subnet_ids.each do |subnet_id|
			  ec2.associate_route_table(
			    subnet_id: subnet_id,
			    route_table_id: public_rt_id
			  )
			end

			#
			# Associate Private Subnets
			#
			private_subnet_ids.each do |subnet_id|
			  ec2.associate_route_table(
			    subnet_id: subnet_id,
			    route_table_id: private_rt_id
			  )
			end

			#
			# Default Security Group
			#
			sg = ec2.create_security_group(
			  group_name: "#{environment}-default-sg",
			  description: "Default security group",
			  vpc_id: vpc_id
			)

			sg_id = sg.group_id

			ec2.authorize_security_group_ingress(
			  group_id: sg_id,
			  ip_permissions: [
			    {
			      ip_protocol: "-1",
			      user_id_group_pairs: [
			        {
			          group_id: sg_id
			        }
			      ]
			    }
			  ]
			)

			ec2.authorize_security_group_egress(
			  group_id: sg_id,
			  ip_permissions: [
			    {
			      ip_protocol: "-1",
			      user_id_group_pairs: [
			        {
			          group_id: sg_id
			        }
			      ]
			    }
			  ]
			)

			tag_resource(sg_id,
			  "Environment" => environment
			)

			{
			  vpc_id: vpc_id,
			  public_subnet_ids: public_subnet_ids,
			  private_subnet_ids: private_subnet_ids,
			  nat_gateway_id: nat_gateway_id,
			  internet_gateway_id: igw_id,
			  security_group_id: sg_id
			}
		end

		private

		def tag_resource(resource_id, tags)
			ec2.create_tags(
			  resources: [resource_id],
			  tags: tags.map do |k, v|
			    { key: k, value: v }
			  end
			)
		end

		def wait_for_nat_gateway(nat_gateway_id)
			loop do
			  nat = ec2.describe_nat_gateways(
			    nat_gateway_ids: [nat_gateway_id]
			  ).nat_gateways.first

			  case nat.state
			  when "available"
			    return
			  when "failed"
			    raise "NAT Gateway creation failed"
			  end

			  sleep 15
			end
		end
	end
end