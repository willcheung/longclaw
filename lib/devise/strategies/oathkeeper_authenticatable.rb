module Devise
  module Strategies
    class OathkeeperAuthenticatable < Authenticatable
      def valid?
        puts "========================", "OathkeeperAuthenticatable Strategy .valid?", "========================="
        super
      end

      #
      # For an example check : https://github.com/plataformatec/devise/blob/master/lib/devise/strategies/database_authenticatable.rb
      #
      # Method called by warden to authenticate a resource.
      #
      def authenticate!
        puts "========================", "OathkeeperAuthenticatable Strategy .authenticate!", "========================="
        #
        # authentication_hash doesn't include the password
        #
        auth_params = authentication_hash
        auth_params[:password] = password

        p auth_params

        #
        # mapping.to is a wrapper over the resource model
        #
        resource = mapping.to.new

        p resource

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