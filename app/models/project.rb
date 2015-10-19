# == Schema Information
#
# Table name: projects
#
#  id                 :uuid             not null, primary key
#  name               :string           default(""), not null
#  account_id         :uuid
#  project_code       :string
#  is_billable        :boolean          default(TRUE)
#  status             :string
#  description        :text
#  planned_start_date :date
#  planned_end_date   :date
#  actual_start_date  :date
#  actual_end_date    :date
#  budgeted_hours     :integer
#  created_by         :uuid
#  updated_by         :uuid
#  owner_id           :uuid
#  is_template        :boolean          default(FALSE)
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#

class Project < ActiveRecord::Base
	belongs_to 	:account
	belongs_to	:user, foreign_key: "owner_id"
	has_many	:project_members
	has_many	:contacts, through: "project_members"

	validates :name, presence: true, uniqueness: { scope: :account, message: "There's already an project with the same name." }
	validates :budgeted_hours, numericality: { only_integer: true, allow_blank: true }

	STATUS = ["Active", "Completed", "On Hold", "Cancelled", "Archived"]

end
