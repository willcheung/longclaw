# Subclass the GoogleOauth2 Omniauth strategy for
# Google Apps Marketplace V2 SSO.
module OmniAuth
  module Strategies
    class GoogleAppsMarketplace < OmniAuth::Strategies::GoogleOauth2
      option :name, 'google_apps_marketplace'
    end
  end
end