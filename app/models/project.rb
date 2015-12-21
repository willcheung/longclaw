# == Schema Information
#
# Table name: projects
#
#  id             :uuid             not null, primary key
#  name           :string           default(""), not null
#  account_id     :uuid
#  project_code   :string
#  is_billable    :boolean          default(TRUE)
#  status         :string
#  description    :text
#  start_date     :date
#  end_date       :date
#  budgeted_hours :integer
#  created_by     :uuid
#  updated_by     :uuid
#  owner_id       :uuid
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#

class Project < ActiveRecord::Base
	belongs_to 	:account
	belongs_to	:project_owner, class_name: "User", foreign_key: "owner_id"
	has_many	:project_members
	has_many	:contacts, through: "project_members"
	has_many	:activities

	validates :name, presence: true, uniqueness: { scope: :account, message: "There's already an project with the same name." }
	validates :budgeted_hours, numericality: { only_integer: true, allow_blank: true }

	STATUS = ["Active", "Completed", "On Hold", "Cancelled", "Archived"]

	# http://192.168.1.130:8888/newsfeed/search?email=indifferenzetester@gmail.com&token=ya29.UAJP6r81Qf9YXosd8S2a61JlTyL6WmqpZ9zAtThBs5z8sEfIMwwNKPxfVNmqWgyustfcy7g&max=10&ex_clusters=[[patrick.smith@clarizen.com]]

	def self.create_from_clusters()

	end
end
