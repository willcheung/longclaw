class SettingsController < ApplicationController

	def sasuke
		puts '===='
		puts request.env["omniauth.auth"]
		puts '====='
 	end
	
	def index
		@users = current_user.organization.users
		@accounts = Account.eager_load(:projects, :user).where('accounts.organization_id = ? and (projects.id IS NULL OR projects.is_public=true OR (projects.is_public=false AND projects.owner_id = ?))', current_user.organization_id, current_user.id).order("lower(accounts.name)")

        @salesforce_user = OauthUser.find_by(oauth_instance_url: ENV['salesforce_url_instance'], organization_id: current_user.organization_id)
        @salesforce_accounts = []

        if(!@salesforce_user.nil?)
        	client = Restforce.new :oauth_token => @salesforce_user.oauth_access_token,
                                  :refresh_token => @salesforce_user.oauth_refresh_token,
                                  :instance_url => @salesforce_user.oauth_instance_url,
                                  :client_id => ENV['salesforce_client_id'],
                                  :client_secret => ENV['salesforce_client_secret']


  							

  								puts '================'
  								puts client.to_yaml
  								puts '================'
          begin
  					@salesforce_accounts = client.query("select Id, Name from Account ORDER BY Name")
  			  rescue  
  			  	# salesforce refresh token expires when different app use it for 5 times
  			  	@salesforce_user.destroy
  			  	respond_to do |format|
      				format.html { redirect_to settings_url }
    				end
  			  end
        end      
	end

	def super_user
		@super_admin = %w(willycheung@gmail.com indifferenzetester@gmail.com wcheung@contextsmith.com)
		if @super_admin.include?(current_user.email)
			@users = User.registered.all
		else
			redirect_to root_path
		end
	end

	def invite_user
		@user = User.find_by_id(params[:user_id])

		UserMailer.user_invitation_email(@user, get_full_name(current_user), new_user_registration_url(invited_by: current_user.first_name)).deliver_later

		respond_to do |format|
			format.js
		end
	end
end