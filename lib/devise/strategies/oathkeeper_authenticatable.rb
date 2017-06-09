module Devise
  module Strategies
    class OathkeeperAuthenticatable < Authenticatable
      def valid?
        puts "valid?"
        # super = valid_for_params_auth? || valid_for_http_auth?
        # def valid_for_params_auth?
        #   params_authenticatable? && valid_params_request? &&
        #     valid_params? && with_authentication_hash(:params_auth, params_auth_hash)
        # end
        # p params_authenticatable?
        # p valid_params_request?
        # p valid_params?
        # p with_authentication_hash(:params_auth, params_auth_hash) if params_authenticatable? && valid_params_request? && valid_params?

        # params_authenticatable? && valid_params?
        super
      end

      def authenticate!
        puts "authenticate!"
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