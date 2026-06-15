# frozen_string_literal: true

require_relative "radioactive_toy/version"
require_relative "radioactive_toy/deployer"
require "radioactive_toy/railtie" if defined?(Rails)

module RadioactiveToy
  autoload :Client, "radioactive_toy/client"
  autoload :Deployer, "radioactive_toy/deployer"
end
