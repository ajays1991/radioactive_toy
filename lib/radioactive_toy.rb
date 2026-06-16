# frozen_string_literal: true

require_relative "radioactive_toy/version"
require_relative "radioactive_toy/deployer"
require "radioactive_toy/railtie" if defined?(Rails)

module RadioactiveToy
  autoload :Client, "radioactive_toy/client"
  autoload :Deployer, "radioactive_toy/deployer"
  autoload :NetworkProvisioner, "radioactive_toy/network_provisioner"
  autoload :EcsProvisioner, "radioactive_toy/ecs_provisioner"
  autoload :EksProvisioner, "radioactive_toy/eks_provisioner"
  autoload :ElasticCacheProvisioner, "radioactive_toy/elastic_cache_provisioner"
  autoload :RdsProvisioner, "radioactive_toy/rds_provisioner"
  autoload :GithubProvisioner, "radioactive_toy/github_provisioner"
  autoload :GitlabProvisioner, "radioactive_toy/gitlab_provisioner"
  autoload :BitbucketProvisioner, "radioactive_toy/bitbucket_provisioner"
end
