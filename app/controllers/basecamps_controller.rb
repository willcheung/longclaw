require_dependency "app/services/basecamp_service.rb"

class BasecampsController < ApplicationController
	layout "empty", only: [:index]

	def index
		
	end

	def basecamp2
		puts "Hello Basecamp Controller basecamp2"
		OauthUser.oauth_basecamp2

		redirect_to BaseCampService.connect_basecamp2
	end


end
