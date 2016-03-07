class SettingsController < ApplicationController
	
	def index
		super_admin = %w(willycheung@gmail.com indifferenzetester@gmail.com wcheung@contextsmith.com)

		if super_admin.include?(current_user.email)
			@users = User.registered.all
		else
			redirect_to root_path
		end
	end
end