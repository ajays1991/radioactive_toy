module RadioactiveToy
  class Deployer
    def deploy
      client = Client.new
      client.deploy
    end
  end
end