require Rails.root.join('lib/devise/strategies/oathkeeper_authenticatable').to_s

module Devise
  module Models
    module OathkeeperAuthenticatable
      extend ActiveSupport::Concern

      #
      # Here you do the request to the external webservice
      #
      # If the authentication is successful you should return
      # a resource instance
      #
      # If the authentication fails you should return false
      #
      def oathkeeper_authentication(authentication_hash)
        # Your logic to authenticate with the external webservice
        puts "========================", "OathkeeperAuthenticatable Models/Concern .oathkeeper_authentication", "========================="
        p "testing auth fail..."
        false
      end

      # module ClassMethods
      #   ####################################
      #   # Overriden methods from Devise::Models::Authenticatable
      #   ####################################

      #   #
      #   # This method is called from:
      #   # Warden::SessionSerializer in devise
      #   #
      #   # It takes as many params as elements had the array
      #   # returned in serialize_into_session
      #   #
      #   # Recreates a resource from session data
      #   #
      #   def serialize_from_session(id)
      #     resource = self.new
      #     resource.id = id
      #     resource
      #   end

      #   #
      #   # Here you have to return and array with the data of your resource
      #   # that you want to serialize into the session
      #   #
      #   # You might want to include some authentication data
      #   #
      #   def serialize_into_session(record)
      #     [record.id]
      #   end

      # end
    end
  end
end