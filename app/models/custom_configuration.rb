# == Schema Information
#
# Table name: custom_configurations
#
#  id              :integer          not null, primary key
#  organization_id :uuid             not null
#  user_id         :uuid
#  config_type     :string           not null
#  config_value    :string           default(""), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#
# Indexes
#
#  idx_custom_configurations  (organization_id,user_id,config_type) UNIQUE
#

# This is for saving configurations that are not directly accessible in the User's Settings page
class CustomConfiguration < ActiveRecord::Base
	belongs_to  :organization
	belongs_to  :user
end
