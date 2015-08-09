# == Schema Information
#
# Table name: accounts
#
#  id              :uuid             not null, primary key
#  name            :string           default(""), not null
#  description     :text             default("")
#  website         :string
#  owner_id        :uuid
#  phone           :string
#  address         :text
#  created_by      :uuid
#  updated_by      :uuid
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  organization_id :uuid
#  notes           :text
#  status          :string
#

class Account < ActiveRecord::Base
	has_many 		:contacts
	has_many		:projects
	belongs_to	:organization
	belongs_to	:user, foreign_key: "owner_id"

	validates :name, presence: true, uniqueness: { scope: :organization, message: "There's already an account with the same name." }

	STATUS = %w(Active Inactive Dead)
end
