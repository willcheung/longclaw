module Devise
  module Strategies
    class OathkeeperAuthenticatable < Authenticatable
      def authenticate!
        resource = password.present? && (mapping.to.find_for_database_authentication(authentication_hash) || mapping.to.new(authentication_hash))
        return fail unless resource

        if validate(resource) { resource.oathkeeper_authentication(password, params[:user][:hostname]) }
          success!(resource)
        else
          # argument for fail! is passed to flash[:alert] in controllers
          fail!(resource.auth_response["message"])
        end
      end
    end
  end
end

# Register :oathkeeper_authenticatable with Warden
Warden::Strategies.add(:oathkeeper_authenticatable, Devise::Strategies::OathkeeperAuthenticatable)