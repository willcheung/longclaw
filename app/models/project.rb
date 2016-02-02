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
# Indexes
#
#  index_projects_on_account_id  (account_id)
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

	scope :visible_to, -> (organization_id, user_id) {
		select("DISTINCT(projects.*)").joins([:project_members,:account]).where("accounts.organization_id = ? AND is_confirmed = true AND (projects.is_public=true OR (projects.is_public=false AND projects.owner_id = ?) OR project_members.user_id = ?)", organization_id, user_id, user_id).group("projects.id")
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

	def self.count_activities_by_day(days_ago, array_of_project_ids)
		metrics = {}
    previous = nil
    arr = []
		days_ago_sql = "(CURRENT_DATE - INTERVAL '#{days_ago-1} days')"

		query = <<-SQL
      WITH time_series as (
        SELECT * 
          from (SELECT generate_series(date #{days_ago_sql}, CURRENT_DATE, INTERVAL '1 day') as days) t1 
                CROSS JOIN 
               (SELECT id as project_id from projects where id in ('#{array_of_project_ids.join("','")}')) t2)
      SELECT time_series.project_id, time_series.days, count(activities.*) as count_activities
      FROM time_series
      LEFT JOIN (SELECT last_sent_date::date, project_id 
                    FROM activities 
                    WHERE activities.last_sent_date > #{days_ago_sql}) as activities
        ON activities.project_id = time_series.project_id and activities.last_sent_date = time_series.days
      GROUP BY time_series.project_id, days 
      ORDER BY time_series.project_id, days ASC
    SQL

    last_7d_activities = Project.find_by_sql(query)

		last_7d_activities.each_with_index do |p,i|
      if previous.nil?
        arr << p.count_activities
        previous = p.project_id
      else
        if previous == p.project_id
          arr << p.count_activities
        else
          metrics[previous] = arr
          arr = []
          arr << p.count_activities
        end
        previous = p.project_id
      end

      if last_7d_activities[i+1].nil?
        metrics[previous] = arr
      end
    end

    return metrics
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
