# == Schema Information
#
# Table name: projects
#
#  id             :uuid             not null, primary key
#  name           :string           default(""), not null
#  account_id     :uuid
#  project_code   :string
#  is_public      :boolean          default(TRUE)
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
#  is_confirmed   :boolean
#

include Utils
include ContextSmithParser

class Project < ActiveRecord::Base
	belongs_to 	:account
	belongs_to	:project_owner, class_name: "User", foreign_key: "owner_id"
	has_many	:project_members, dependent: :destroy
	has_many	:activities, -> { order "last_sent_date DESC" }, dependent: :destroy
	has_many	:contacts, through: "project_members"
	has_many	:users, through: "project_members"

	scope :visible_to, -> (user_id) {
		joins(:project_members).where("projects.is_public=true OR (projects.is_public=false AND projects.owner_id = ?) OR project_members.user_id = ?", user_id, user_id).group("projects.id")
	}
	scope :is_active, -> {where("projects.status = 'Active'")}

	validates :name, presence: true, uniqueness: { scope: [:account, :project_owner, :is_confirmed], message: "There's already an project with the same name." }
	validates :budgeted_hours, numericality: { only_integer: true, allow_blank: true }

	STATUS = ["Active", "Completed", "On Hold", "Cancelled", "Archived"]

	# http://192.168.1.130:8888/newsfeed/search?email=indifferenzetester@gmail.com&token=ya29.UAJP6r81Qf9YXosd8S2a61JlTyL6WmqpZ9zAtThBs5z8sEfIMwwNKPxfVNmqWgyustfcy7g&max=10&ex_clusters=[[patrick.smith@clarizen.com]]

	def self.check_existing_from_clusters(data, user_id, organization_id)
		# Use Dice Coefficient
		# Everything lives in OnboardingController#confirm_projects right now
	end

	# This method should be called *after* all accounts, contacts, and users are processed & inserted.
	def self.create_from_clusters(data, user_id, organization_id)
		project_domains = get_project_top_domain(data)
		accounts = Account.where(domain: project_domains, organization_id: organization_id)
		
		project_domains.each do |p|
			external_members, internal_members = get_project_members(data, p)
			project = Project.new(name: (accounts.find {|a| a.domain == p}).name + " Project",
													 status: "Active",
													 created_by: user_id,
													 updated_by: user_id,
													 owner_id: user_id,
													 account_id: (accounts.find {|a| a.domain == p}).id,
													 is_public: true,
													 is_confirmed: false # This needs to be false during onboarding so it doesn't get read as real projects
													)
			
			if project.save
				# Project members
				# assuming contacts and users have already been inserted, we just need to link them
				contacts = Contact.where(email: external_members.map(&:address)).joins(:account).where("accounts.organization_id = ?", organization_id)
				users = User.where(email: internal_members.map(&:address), organization_id: organization_id)
				
				external_members.each do |m|
					puts (contacts.find {|c| c.email == m.address}).id
					project.project_members.create(contact_id: (contacts.find {|c| c.email == m.address}).id)
				end

				internal_members.each do |m|
					project.project_members.create(user_id: (users.find {|c| c.email == m.address}).id)
				end

				# Project activities
				Activity.load(get_project_conversations(data, p), project, user_id)
			end
		end
	end
end
