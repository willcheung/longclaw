# == Schema Information
#
# Table name: projects
#
#  id             :uuid             not null, primary key
#  name           :string           default(""), not null
#  account_id     :uuid
#  project_code   :string
#  is_public      :boolean          default(TRUE)
#  status         :string           default("Active")
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
#  category       :string           default("Implementation")
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
	has_many  :subscribers, class_name: "ProjectSubscriber", dependent: :destroy

	scope :visible_to, -> (organization_id, user_id) {
		select('DISTINCT(projects.*)')
				.joins([:account, 'LEFT OUTER JOIN project_members ON project_members.project_id = projects.id'])
				.where('accounts.organization_id = ? AND projects.is_confirmed = true AND projects.status = \'Active\' AND (projects.is_public=true OR (projects.is_public=false AND projects.owner_id = ?) OR project_members.user_id = ?)',
							 organization_id, user_id, user_id)
				.group('projects.id')
	}
	# Only using this for Daily Summaries
	scope :following, -> (user_id) {
		joins("INNER JOIN project_subscribers ON project_subscribers.project_id = projects.id")
		.where("project_subscribers.user_id = ?", user_id)
	}
	scope :is_active, -> {where("projects.status = 'Active'")}

	validates :name, presence: true, uniqueness: { scope: [:account, :project_owner, :is_confirmed], message: "There's already an project with the same name." }
	validates :budgeted_hours, numericality: { only_integer: true, allow_blank: true }

	STATUS = ["Active", "Completed", "On Hold", "Cancelled", "Archived"]
	CATEGORY = { Implementation: 'Implementation', Onboarding: 'Onboarding', Pilot: 'Pilot', Support: 'Support', Other: 'Other' }

	attr_accessor :num_activities_prev, :pct_from_prev

	def self.check_existing_from_clusters(data, user_id, organization_id)
		# Use Dice Coefficient
		# Everything lives in OnboardingController#confirm_projects right now
	end

	def self.find_include_count_activities_by_day(array_of_project_ids, time_zone)
		metrics = {}
    previous = nil
    arr = []

		query = <<-SQL
      WITH time_series as (
        SELECT * 
          from (SELECT generate_series(date (CURRENT_DATE - INTERVAL '14 days'), CURRENT_DATE, INTERVAL '1 day') as days) t1 
                CROSS JOIN 
               (SELECT id as project_id from projects where id in ('#{array_of_project_ids.join("','")}')) t2
       )
      SELECT time_series.project_id as id, date(time_series.days) as date, count(activities.*) as num_activities
      FROM time_series
      LEFT JOIN (SELECT sent_date, project_id 
      					 FROM email_activities_last_14d where project_id in ('#{array_of_project_ids.join("','")}')
                 ) as activities
        ON activities.project_id = time_series.project_id and date_trunc('day', to_timestamp(activities.sent_date::integer) AT TIME ZONE '#{time_zone}') = time_series.days
      GROUP BY time_series.project_id, days 
      ORDER BY time_series.project_id, days ASC
    SQL

    Project.find_by_sql(query)
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
               (SELECT id as project_id from projects where id in ('#{array_of_project_ids.join("','")}')) t2
       )
      SELECT time_series.project_id, time_series.days, count(activities.*) as count_activities
      FROM time_series
      LEFT JOIN (SELECT sent_date, project_id from 
      							(SELECT jsonb_array_elements(email_messages) ->> 'sentDate' as sent_date, project_id 
                    	FROM activities where project_id in ('#{array_of_project_ids.join("','")}')
                		) t
                 WHERE t.sent_date::integer > EXTRACT(EPOCH FROM #{days_ago_sql})
                 ) as activities
        ON activities.project_id = time_series.project_id and date_trunc('day', to_timestamp(activities.sent_date::integer)) = time_series.days
      GROUP BY time_series.project_id, days 
      ORDER BY time_series.project_id, days ASC
    SQL

    activities = Project.find_by_sql(query)

		activities.each_with_index do |p,i|
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

      if activities[i+1].nil?
        metrics[previous] = arr
      end
    end

  	return metrics
  end

  def self.find_include_sum_activities(hours_ago_end=Date.current, hours_ago_start, array_of_project_ids)
		hours_ago_end_sql = (hours_ago_end == Date.current) ? 'CURRENT_TIMESTAMP' : "CURRENT_TIMESTAMP - INTERVAL '#{hours_ago_end} hours'"
  	hours_ago_start_sql = "INTERVAL '#{hours_ago_start} hours'"

  	query = <<-SQL
  		SELECT projects.*, count(*) as num_activities from (
				SELECT id, 
							 backend_id, 
							 last_sent_date, 
							 project_id, 
							 jsonb_array_elements(email_messages) ->> 'sentDate' as sent_date 
					from activities where project_id in ('#{array_of_project_ids.join("','")}')
				) t 
			JOIN projects ON projects.id = t.project_id
			WHERE sent_date::integer between EXTRACT(EPOCH FROM CURRENT_TIMESTAMP - #{hours_ago_start_sql})::integer and EXTRACT(EPOCH FROM #{hours_ago_end_sql})::integer 
			GROUP BY projects.id
			ORDER BY num_activities DESC
		SQL

		return Project.find_by_sql(query)
  end

	# This method should be called *after* all accounts, contacts, and users are processed & inserted.
	def self.create_from_clusters(data, user_id, organization_id)
		project_domains = get_project_top_domain(data)
		accounts = Account.where(domain: project_domains, organization_id: organization_id)
		
		project_domains.each do |p|
			external_members, internal_members = get_project_members(data, p)
			project = Project.new(name: (accounts.find {|a| a.domain == p}).name + " Project",
													 status: "Active",
													 category: "Implementation",
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
					project.project_members.create(contact_id: (contacts.find {|c| c.email == m.address}).id)
				end

				internal_members.each do |m|
					project.project_members.create(user_id: (users.find {|c| c.email == m.address}).id)
				end

				# Automatically subscribe to projects created
				project.subscribers.create(user_id: current_user.id)

				# Project activities
				Activity.load(get_project_conversations(data, p), project, user_id)
			end
		end
	end

	def self.calculate_pct_from_prev(project, project_prev)
		project_chg_activities = []

		project.each do |p|
      project_prev.each do |p_prev|
        if p.id == p_prev.id
          p.num_activities_prev = p_prev.num_activities
          p.pct_from_prev = (((p.num_activities - p_prev.num_activities) / p_prev.num_activities.to_f) * 100).round(1)
          project_chg_activities << p
        end
      end
    end
    return project_chg_activities
	end

end
