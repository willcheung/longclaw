module Devise
  module Strategies
    class OathkeeperAuthenticatable < Authenticatable
      # def authenticate!
      #   puts "OathkeeperAuthenticatable Strategy .authenticate!", "========================="
      #   # authentication_hash doesn't include the password, pass through from params[:user]
      #   auth_params = authentication_hash
      #   auth_params[:password] = params[:user][:password]

      #   # mapping.to is a wrapper over the resource model (for now, should be User)
      #   resource = mapping.to.new

      #   return fail! unless resource

      #   # oathkeeper_authentication method is defined in Devise::Models::OathkeeperAuthenticatable
      #   #
      #   # validate is a method defined in Devise::Strategies::Authenticatable. It takes
      #   # a block which must return a boolean value.
      #   #
      #   # If the block returns true the resource will be loged in
      #   # If the block returns false the authentication will fail!
      #   #
      #   if validate(resource) { resource.oathkeeper_authentication(auth_params) }
      #     success!(resource)
      #   else
      #     fail!
      #   end
      # end

      def authenticate!
        resource  = password.present? && (mapping.to.find_for_database_authentication(authentication_hash) || mapping.to.new(authentication_hash))        

        if validate(resource) { resource.oathkeeper_authentication(password) }
          # remember_me(resource)
          resource.after_database_authentication
          success!(resource)
        end

        # mapping.to.new.password = password if !encrypted && Devise.paranoid
        fail(:not_found_in_database) unless resource
      end
    end
  end
end

# Register :oathkeeper_authenticatable with Warden
Warden::Strategies.add(:oathkeeper_authenticatable, Devise::Strategies::OathkeeperAuthenticatable)