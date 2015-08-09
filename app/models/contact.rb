# == Schema Information
#
# Table name: contacts
#
#  id         :uuid             not null, primary key
#  account_id :uuid
#  first_name :string           default(""), not null
#  last_name  :string           default(""), not null
#  email      :string           default(""), not null
#  phone      :string           default(""), not null
#  title      :string           default(""), not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#

class Contact < ActiveRecord::Base
	belongs_to :account
	has_many :project_members
	has_many :projects, through: "project_members"
end
