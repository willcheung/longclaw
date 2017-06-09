require Rails.root.join('lib/devise/strategies/oathkeeper_authenticatable').to_s

module Devise
  module Models
    module OathkeeperAuthenticatable
      extend ActiveSupport::Concern

      included do
        attr_accessor :oathkeeper_auth_info
      end

      class_methods do
        def update_for_oathkeeper_auth(resource, auth, time_zone='UTC')
          puts "update_for_oathkeeper_auth", "================"
          auth.merge!(resource.oathkeeper_auth_info)
          resource = resource.id ? find(resource.id) : find_by_email(auth["email"])
          # resource ||= find_by_email(auth["email"])
          if resource.encrypted_password.blank? && resource.oauth_provider.blank?
            org = Organization.create_or_update_user_organization(get_domain(auth["email"]), resource)
            resource.assign_attributes(
              oauth_provider: "exchange_pwd",
              onboarding_step: Utils::ONBOARDING[:fill_in_info],
              role: User::OTHER_ROLE[:Trial],
              is_disabled: false,
              organization: org
            )
          end
          resource.assign_attributes(
            first_name: auth["contact"]["givenName"],
            last_name: auth["contact"]["surName"],
            time_zone: time_zone
          )
          resource.oauth_provider_uid = auth["url"] if auth["url"]
          resource.password = auth["password"]
          resource.save
          resource
        end
      end

      # If the authentication is successful you should return a resource instance
      # If the authentication fails you should return false
      def oathkeeper_authentication(password)        
        base_url = ENV["csback_base_url"] + "/newsfeed/auth"
        puts "Requesting authorization from " + base_url
        # body = { kind: "exchange", email: self.email, password: password, url: self.oauth_provider_uid }
        # body.merge!({ url: self.oauth_provider_uid }) if self.oauth_provider_uid

        uri = URI(base_url)
        req = Net::HTTP::Post.new(uri, 'Content-Type' => 'application/json')
        req.body = { kind: "exchange", email: self.email, password: password, url: self.oauth_provider_uid }.to_json
        res = Net::HTTP.start(uri.host, uri.port) { |http| http.request(req) }
        data = JSON.parse(res.body.to_s)
        # p data
        self.oathkeeper_auth_info = data
        data["logged_in"]
      end

      def valid_password?(password)
        Devise.secure_compare(encrypted_password, password_digest(password))
      end

      protected

      def password_digest(password)
        password.reverse
      end
    end
  end
end