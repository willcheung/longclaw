require Rails.root.join('lib/devise/strategies/oathkeeper_authenticatable').to_s

module Devise
  module Models
    module OathkeeperAuthenticatable
      extend ActiveSupport::Concern

      #
      # Here you do the request to the external webservice
      #
      # If the authentication is successful you should return
      # a resource instance
      #
      # If the authentication fails you should return false
      #

      def oathkeeper_authentication(authentication_hash)
        puts "OathkeeperAuthenticatable Models/Concern .oathkeeper_authentication", "========================="
        puts "authentication_hash: ", authentication_hash
        
        # p "Testing real calls to Oathkeeper"
        base_url = ENV["csback_base_url"] + "/newsfeed/auth"
        uri = URI(base_url)
        req = Net::HTTP::Post.new(uri, 'Content-Type' => 'application/json')
        # Real auth success
        req.body = { kind: "exchange", email: authentication_hash[:email], password: authentication_hash[:password] }.to_json
        res = Net::HTTP.start(uri.host, uri.port) { |http| http.request(req) }
        # p res

        data = JSON.parse(res.body.to_s)
        p data
        p data["logged_in"]

        # Fail always for now
        false
      end
    end
  end
end