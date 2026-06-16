# frozen_string_literal: true

require_relative "radioactive_toy/version"
require_relative "radioactive_toy/deployer"
require "radioactive_toy/railtie" if defined?(Rails)

module RadioactiveToy
  autoload :Client, "radioactive_toy/client"
  autoload :Deployer, "radioactive_toy/deployer"
  autoload :NetworkProvisioner, "radioactive_toy/network_provisioner"
  autoload :EcsProvisioner, "radioactive_toy/ecs_provisioner"
end
