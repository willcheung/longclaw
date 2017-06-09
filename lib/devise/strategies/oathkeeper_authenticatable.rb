module Devise
  module Strategies
    class OathkeeperAuthenticatable < Authenticatable
      def authenticate!
        resource = password.present? && (mapping.to.find_for_database_authentication(authentication_hash) || mapping.to.new(authentication_hash))        

        if validate(resource) { resource.oathkeeper_authentication(password) }
          success!(resource)
        else
          fail!
        end
      end
    end
  end
end

# Register :oathkeeper_authenticatable with Warden
Warden::Strategies.add(:oathkeeper_authenticatable, Devise::Strategies::OathkeeperAuthenticatable)