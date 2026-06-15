# lib/radioactive_toy/railtie.rb

module RadioactiveToy
  class Railtie < Rails::Railtie
    initializer "radioactive_toy.initialize" do
      puts "RadioactiveToy loaded"
    end

    generators do
      require_relative "../generators/radioactive_toy/deploy_generator"
    end

    rake_tasks do
      load File.expand_path("../../tasks/radioactive_toy_tasks.rake", __FILE__)
    end
  end
end