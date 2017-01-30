# Subclass the GoogleOauth2 Omniauth strategy for
# Google Apps Marketplace V2 SSO.

# require 'basecamp2'
# Not being used right now.
# module OmniAuth
#   module Strategies
#     class GoogleAppsMarketplace < OmniAuth::Strategies::GoogleOauth2
#       option :name, 'google_apps_marketplace'
#     end
#   end
# end

# module OmniAuth
# 	module Strategies
# 		autoload :basecamp2, 'service/basecamp_strategy'
# 	end
# end

# Rails.application.config.middleware.use OmniAuth::Builder do 
# 	provider :basecamp2, ENV['basecamp_client_id'], ENV['basecamp_client_secret']
# end