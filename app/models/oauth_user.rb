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
#
# Indexes
#
#  oauth_per_user  (oauth_provider,oauth_user_name,oauth_instance_url) UNIQUE
#

class OauthUser < ActiveRecord::Base
	belongs_to 	:organization
end
