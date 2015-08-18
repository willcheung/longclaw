# == Schema Information
#
# Table name: contacts
#
#  id              :uuid             not null, primary key
#  account_id      :uuid
#  first_name      :string           default(""), not null
#  last_name       :string           default(""), not null
#  email           :string(64)       default(""), not null
#  phone           :string(32)       default(""), not null
#  title           :string           default(""), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  alt_email       :string(64)
#  mobile          :string(32)
#  background_info :text
#  department      :string
#

class Contact < ActiveRecord::Base
	belongs_to :account
	has_many :project_members
	has_many :projects, through: "project_members"
end
