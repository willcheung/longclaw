# == Schema Information
require_dependency "app/services/basecamp_service.rb"
#
# Table name: oauth_users
#
#  id                  :integer          not null, primary key
#  oauth_provider      :string           not null
#  oauth_provider_uid  :string           not null
#  oauth_access_token  :string           not null
#  oauth_refresh_token :string
#  oauth_instance_url  :string           not null
#  oauth_user_name     :string           default(""), not null
#  organization_id     :uuid             not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#
# Indexes
#
#  oauth_per_user  (oauth_provider,oauth_user_name,oauth_instance_url) UNIQUE
#

class OauthUser < ActiveRecord::Base
	belongs_to 	:organization
	belongs_to :user



	def self.oauth_basecamp2(organization_id)


		puts "Hello from OauthUser modal organization_id: #{organization_id}"


		redirect_uri = 'http://localhost:3000/users/auth/37signals/callback'

		basecamp_authorization_url = 'https://launchpad.37signals.com/authorization/new'
  		basecamp_token_url = 'https://launchpad.37signals.com/authorization/token'
  		site = 'https://launchpad.37signals.com/authorization/new?type=web_server'
  		# Create a Client
		@client = OAuth2::Client.new( ENV['basecamp_client_id'], ENV[basecamp_client_secret], :authorize_url => basecamp_authorization_url, :token_url => basecamp_token_url, :site => 'https://launchpad.37signals.com/authorization/new?type=web_server')
	end

	def self.basecamp2_user_projects(token)
		#this is what BaseCampServices returns if user projects is found

		#RETURN JSON:
							# {
							# 	"id"=>13487410,
							# 	"name"=>"Basecamp 2 Integration",
							# 	"description"=>"learning all about basecamp2",
							# 	"archived"=>false,
							# 	"is_client_project"=>false,
							# 	"created_at"=>"2017-01-18T15:01:29.000-08:00",
							# 	"updated_at"=>"2017-01-24T17:44:45.000-08:00",
							# 	"trashed"=>false,
							# 	"color"=>"aa0000",
							# 	"draft"=>false,
							# 	"template"=>false,
							# 	"last_event_at"=>"2017-01-24T17:44:45.000-08:00", 
							# 	"starred"=>true, 
							# 	"url"=>"https://basecamp.com/3643958/api/v1/projects/13487410.json",
							# 	"app_url"=>"https://basecamp.com/3643958/projects/13487410"
							# }

		puts "Basecamp2Userproejcts Modal"
		BaseCampService.basecamp2_user_projects(token)
	end

	def self.basecamp_token(token)
		puts "hello basecamp Token #{token}"
	end
end









