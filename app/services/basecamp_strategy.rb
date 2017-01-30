require 'omniauth-oauth2'
require 'oauth2'
require 'json'

module OmniAuth
	module Strategies
		class BaseCamp2 < OmniAuth::Strategies::OAuth2

			client_id = 'a708737faac642403a3b8fb000585ace49fd1935'
	  	client_secret = 'efd66e0c5c0ad9b43d5332646d994bf6eb4334a6'
			redirect_uri = 'http://localhost:3000/users/auth/37signals/callback'
			basecamp_authorization_url = 'https://launchpad.37signals.com/authorization/new'
	  	basecamp_token_url = 'https://launchpad.37signals.com/authorization/token'
	  	site = 'https://launchpad.37signals.com/authorization/new?type=web_server'


			# Strategy name
			option :name, "basecamp2"

			#This is where a pass the option you would pass when 
			#initializing your consumer from the Oauth gem.

			option :client_options, {
								client_id, 
								client_secret, 
								:authorize_url => basecamp_authorization_url,
								:token_url => basecamp_token_url,
								:site => 'https://launchpad.37signals.com/authorization/new?type=web_server'
							}

			uid { raw_info['id'] }

      info do
        {
          :email => raw_info['email']
        }
      end

      extra do
        {
          :first_name => raw_info['extra']['first_name'],
          :last_name  => raw_info['extra']['last_name']
        }
      end

      def raw_info
        @raw_info ||= access_token.get("/auth/agencyea/user.json?oauth_token=#{access_token.token}").parsed
      end

		end
	end
end


				