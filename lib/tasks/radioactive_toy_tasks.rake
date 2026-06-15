namespace :radioactive_toy do
  desc "Deploy application"

  task deploy: :environment do
    RadioactiveToy::Deployer.new.deploy
  end
end