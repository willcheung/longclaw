# == Schema Information
#
# Table name: oauth_users
#
#  id                  :integer          not null, primary key
#  organization_id     :uuid             not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  oauth_key           :string           default("")
#  oauth_id            :string           default("")
#  oauth_provider_uid  :string           default("")
#  oauth_user_name     :string           default("")
#  oauth_provider      :string           default("")
#  oauth_access_token  :string           default("")
#  oauth_instance_url  :string           default("")
#  oauth_refresh_token :string           default("")
#
# Indexes
#
#  index_oauth_users_on_organization_id  (organization_id)
#  oauth_per_user                        (oauth_provider,oauth_user_name,oauth_instance_url) UNIQUE
#

class OauthUser < ActiveRecord::Base
	belongs_to 	:organization
end
