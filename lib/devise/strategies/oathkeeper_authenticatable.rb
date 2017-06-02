module Devise
  module Strategies
    class OathkeeperAuthenticatable < Authenticatable
      # FROM Devise::Strategies::Authenticatable
      # def valid?
      #   valid_for_params_auth? || valid_for_http_auth?
      # end
      # # Check if this is a valid strategy for params authentication by:
      # #
      # #   * Validating if the model allows params authentication;
      # #   * If the request hits the sessions controller through POST;
      # #   * If the params[scope] returns a hash with credentials;
      # #   * If all authentication keys are present;
      # #
      # def valid_for_params_auth?
      #   params_authenticatable? && valid_params_request? &&
      #     valid_params? && with_authentication_hash(:params_auth, params_auth_hash)
      # end

      def valid?
        puts "OathkeeperAuthenticatable Strategy .valid?", "========================="  
        val = super
        puts "valid? - ", val
        val
      end

      #
      # For an example check : https://github.com/plataformatec/devise/blob/master/lib/devise/strategies/database_authenticatable.rb
      #
      # Method called by warden to authenticate a resource.
      #
      def authenticate!
        puts "OathkeeperAuthenticatable Strategy .authenticate!", "========================="
        #
        # authentication_hash doesn't include the password, pass through from params[:user]
        #
        auth_params = authentication_hash
        auth_params[:password] = params[:user][:password]

        #
        # mapping.to is a wrapper over the resource model
        #
        resource = mapping.to.new

        return fail! unless resource

        # oathkeeper_authentication method is defined in Devise::Models::OathkeeperAuthenticatable
        #
        # validate is a method defined in Devise::Strategies::Authenticatable. It takes
        # a block which must return a boolean value.
        #
        # If the block returns true the resource will be loged in
        # If the block returns false the authentication will fail!
        #
        if validate(resource) { resource.oathkeeper_authentication(auth_params) }
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