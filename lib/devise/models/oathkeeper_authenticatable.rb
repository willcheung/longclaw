require Rails.root.join('lib/devise/strategies/oathkeeper_authenticatable').to_s

module Devise
  module Models
    module OathkeeperAuthenticatable
      extend ActiveSupport::Concern

      included do
        attr_accessor :oathkeeper_error
      end

      # If the authentication is successful you should return a resource instance
      # If the authentication fails you should return false
      def oathkeeper_authentication(password)
        puts "OathkeeperAuthenticatable Models/Concern .oathkeeper_authentication", "========================="
        
        base_url = ENV["csback_base_url"] + "/newsfeed/auth"
        uri = URI(base_url)
        req = Net::HTTP::Post.new(uri, 'Content-Type' => 'application/json')
        req.body = { kind: "exchange", email: email, password: password }.to_json
        res = Net::HTTP.start(uri.host, uri.port) { |http| http.request(req) }
        data = JSON.parse(res.body.to_s)
        p data
        # p data["logged_in"]
        data["logged_in"]
      end

      def valid_password?(password)
        p "valid_password? from OathkeeperAuthenticatable Models/Concern"
        false
      end

      protected

      def password_digest(password)
        password
      end
    end
  end
end