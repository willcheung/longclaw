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
#  first_name          :string           default(""), not null
#  last_name           :string           default(""), not null
#  user_id             :uuid             not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#
# Indexes
#
#  oauth_per_user  (oauth_provider,oauth_provider_uid,oauth_instance_url) UNIQUE
#

class OauthUser < ActiveRecord::Base
	belongs_to 	:user
end
