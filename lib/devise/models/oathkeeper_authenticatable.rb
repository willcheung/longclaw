require Rails.root.join('lib/devise/strategies/oathkeeper_authenticatable').to_s

module Devise
  module Models
    module OathkeeperAuthenticatable
      extend ActiveSupport::Concern

      included do
        attr_accessor :auth_response
        attr_accessor :hostname
      end

      class_methods do
        def update_for_oathkeeper_auth(resource, auth, time_zone='UTC')
          auth.merge!(resource.auth_response)
          auth.merge!({ "url" => resource.hostname }) if resource.hostname.present?
          resource = resource.id ? find(resource.id) : find_by_email(auth["email"])
          # TODO: should add some exception handling here, just in case resource cannot be found
          if resource.encrypted_password.blank? && resource.oauth_provider.blank?
            org = Organization.create_or_update_user_organization(get_domain(auth["email"]), resource)
            resource.assign_attributes(
              oauth_provider: "exchange_pwd",
              onboarding_step: Utils::ONBOARDING[:fill_in_info],
              role: User::ROLE[:Biz],
              is_disabled: false,
              refresh_inbox: true,
              organization: org
            )
          end
          name = auth["contact"]
          first_name = name.present? && name["givenName"].present? ? name["givenName"] : ''
          last_name = name.present? && name["surName"].present? ? name["surName"] : ''
          resource.assign_attributes(
            first_name: first_name,
            last_name: last_name,
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
      def oathkeeper_authentication(password, hostname)        
        base_url = ENV["csback_base_url"] + "/newsfeed/auth"
        puts "Requesting authorization from " + base_url
        body = { kind: "exchange", email: self.email, password: password }
        # if hostname is submitted with form and is not an empty string, check whether it is full url or a partial url
        # if full url was submitted as hostname, use it
        # if partial url was submitted as hostname, try to extract just the hostname part and build the expected url based on default Exchange url format
        # else if hostname was saved with user in column oauth_provider_uid and not submitted with form, use it
        # otherwise, either registering a new user or existing user doesn't know their hostname, don't include url in request body to trigger url autodiscovery from oathkeeper
        if hostname.present?
          uri = Addressable::URI.heuristic_parse(hostname)
          if uri.scheme.nil? || uri.scheme != hostname[0...uri.scheme.length]
            hostname = uri.hostname if uri.hostname.present?
            hostname = "https://#{hostname}/EWS/Exchange.asmx"
          end
          body.merge!({ url: hostname })
          self.hostname = hostname
        elsif self.oauth_provider_uid.present? && hostname.nil?
          body.merge!({ url: self.oauth_provider_uid })
        end

        uri = URI(base_url)
        req = Net::HTTP::Post.new(uri, 'Content-Type' => 'application/json')
        req.body = body.to_json
        res = Net::HTTP.start(uri.host, uri.port, :read_timeout => 90 ) { |http| http.request(req) }
        data = JSON.parse(res.body.to_s)
        self.auth_response = data
        data["logged_in"]
      end

    end
  end
end