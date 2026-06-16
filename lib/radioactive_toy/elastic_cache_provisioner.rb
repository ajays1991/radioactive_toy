require 'aws-sdk-elasticache'

module RadioactiveToy
	class ElasticCacheProvisioner
		attr_reader :ec_elastic_cache

		def initialize(region:, elastic_cache_config:)
			@ec_elastic_cache = Aws::ElastiCache::Client.new(
			  region: region
			)
			@ec_elastic_cache_config = rds_config
		end

		def run
			response = ec_elastic_cache.create_cache_cluster(
			  cache_cluster_id: 'my-redis-cluster',
			  engine: 'redis',
			  cache_node_type: 'cache.t3.micro',
			  num_cache_nodes: 1,
			  port: 6379,
			  tags: [
			    {
			      key: 'Name',
			      value: 'my-redis-cluster'
			    }
			  ]
			)
			puts "---------------------#{response}-----------------------"
		end

		private
	end
end