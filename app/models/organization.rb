# == Schema Information
#
# Table name: organizations
#
#  id         :uuid             not null, primary key
#  name       :string
#  domain     :string
#  is_active  :boolean          default(TRUE)
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  owner_id   :uuid
#

class Organization < ActiveRecord::Base
	has_many :users
	has_many :accounts
end
