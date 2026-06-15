require "rails/generators"

module RadioactiveToy
  module Generators
    class DeployGenerator < Rails::Generators::Base
      def create_file_example
        puts "Deploy generator running..."
      end
    end
  end
end