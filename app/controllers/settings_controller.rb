class SettingsController < ApplicationController
	
	def index
		@users = current_user.organization.users
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