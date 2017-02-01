# == Schema Information
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
#  oauth_refresh_date  :integer
#  oauth_issued_date   :datetime
#
# Indexes
#
#  oauth_per_user  (oauth_provider,oauth_user_name,oauth_instance_url) UNIQUE
#

require_dependency "app/services/basecamp_service.rb"

class OauthUser < ActiveRecord::Base
	belongs_to 	:organization
	belongs_to :user

	def self.basecamp2_create_user(pin, organization_id)

		result = BaseCampService.basecamp2_create_user(pin)
		if result
			user = OauthUser.new(
				oauth_provider: result['oauth_provider'],
				oauth_provider_uid: result['oauth_provider_uid'],
				oauth_access_token: result['oauth_access_token'],
				oauth_refresh_token: result['oauth_refresh_token'],
				oauth_instance_url: result['oauth_instance_url'],
				oauth_user_name: result['oauth_user_name'],
				organization_id: organization_id,
				oauth_refresh_date: result['oauth_refresh_date'],
				oauth_issued_date: Time.now
				)

			if user.valid?
				user.save
			else
				#failed to save
			end
		end
	end

	def self.basecamp2_projects(token)
		BaseCampService.basecamp2_user_projects(token)
	end

	def self.basecamp2_topics(token)
		BaseCampService.basecamp2_user_topics(token)
	end


	def refresh_token
	end





end









