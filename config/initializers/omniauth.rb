# Subclass the GoogleOauth2 Omniauth strategy for
# Google Apps Marketplace V2 SSO.

 module OmniAuth::Strategies
   class GoogleOauth2Basic < GoogleOauth2
     def name
       :google_oauth2_basic
     end
   end
 end

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

