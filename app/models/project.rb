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
#  deleted_at     :datetime
#
# Indexes
#
#  index_projects_on_account_id  (account_id)
#  index_projects_on_deleted_at  (deleted_at)
#

include Utils
include ContextSmithParser

class Project < ActiveRecord::Base
  acts_as_paranoid

	belongs_to 	:account
  belongs_to  :project_owner, class_name: "User", foreign_key: "owner_id"
  has_many  :subscribers, class_name: "ProjectSubscriber", dependent: :destroy
  has_many  :notifications, dependent: :destroy

  has_many  :activities, -> { order last_sent_date: :desc }, dependent: :destroy
  has_many  :conversations, -> { conversations }, class_name: "Activity"
  has_many  :notes, -> { notes }, class_name: "Activity"
  has_many  :meetings, -> { meetings }, class_name: "Activity"
  has_many  :conversations_for_email, -> { 
    conversations.from_yesterday
    .select(:category, :title, :from, :to, :cc, :project_id, :last_sent_date, :is_public, 
      'jsonb_array_length(email_messages) AS num_messages', 
      'email_messages->-1 AS last_msg') }, class_name: "Activity"
  has_many  :notes_for_email, -> { notes.from_yesterday }, class_name: "Activity"
  has_many  :meetings_for_email, -> { meetings.from_yesterday }, class_name: "Activity"

  ### project_members/contacts/users relations have 2 versions
  # v1: only shows confirmed, similar to old logic without project_members.status column
  # v2: "_all" version, ignores status
  has_many  :project_members, -> { confirmed }, dependent: :destroy
  has_many  :project_members_all, class_name: "ProjectMember", dependent: :destroy
  has_many  :contacts, through: "project_members"
  has_many  :contacts_all, through: "project_members_all", source: :contact
  has_many  :users, through: "project_members"
  has_many  :users_all, through: "project_members_all", source: :user

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
	CATEGORY = { Implementation: 'Implementation', Onboarding: 'Onboarding', Opportunity: 'Opportunity', Pilot: 'Pilot', Support: 'Support', Other: 'Other' }

	attr_accessor :num_activities_prev, :pct_from_prev

	def self.check_existing_from_clusters(data, user_id, organization_id)
		# Use Dice Coefficient
		# Everything lives in OnboardingController#confirm_projects right now
	end

  def self.find_min_risk_score_by_day(array_of_project_ids, time_zone, day_range=14)
    start_time_sec = (day_range-1).days.ago.in_time_zone(time_zone).midnight.utc.to_i

    query = <<-SQL
        SELECT activities.id AS id,
               activities.project_id AS project_id,
               messages ->> 'sentDate' AS sent_date,
               jsonb_array_elements(messages->'sentimentItems')->>'score' AS sentiment_score,
               notifications.id AS has_risk,
               notifications.is_complete,
               notifications.complete_date
        FROM activities
        CROSS JOIN LATERAL jsonb_array_elements(email_messages) messages
        LEFT JOIN notifications
        ON activities.id = notifications.activity_id
        AND messages ->> 'messageId' = notifications.message_id
        AND notifications.category = '#{Notification::CATEGORY[:Risk]}'
        WHERE activities.category = '#{Activity::CATEGORY[:Conversation]}'
        AND messages->>'sentimentItems' IS NOT NULL 
        AND activities.project_id IN ('#{array_of_project_ids.join("','")}')
      SQL

    result = Activity.find_by_sql(query)

    # instantiate min_scores as Hash of Arrays of Arrays
    # project_id => [day in day_range][possible scores]
    min_scores = Hash.new()
    # instantiate non_risk_min_score as Hash
    # project_id => lowest score for all scores created before day_range
    non_risk_min_score = Hash.new()

    array_of_project_ids.each do |pid|
      min_scores[pid] = Array.new(day_range) { [] }
      non_risk_min_score[pid] = 0
    end
    
    if result
      result.each do|r|
        sentiment_score = r.sentiment_score.to_f

        # array position for sent date of current sentiment score (0 if before date range)
        date_index = (r.sent_date.to_i - start_time_sec) / (24*60*60)
        date_index = 0 if date_index < 0 

        # array position for end date of current sentiment score, set below
        end_index = nil

        if r.has_risk
          # risk notification found
          if r.is_complete && r.complete_date.to_i >= start_time_sec
            complete_index = (r.complete_date.to_i - start_time_sec) / (24*60*60))
            # consider score for days it is open
            end_index = complete_index-1 
          elsif !r.is_complete
            # consider score for all days after it was created
            end_index = day_range-1 
          end
        else
          # no risk notification, can't be closed
          if sentiment_score < non_risk_min_score[r.project_id]
            if r.sent_date.to_i < start_time_sec
              # min score from before day_range, will add to consideration later
              non_risk_min_score[r.project_id] = sentiment_score 
            else
              # consider score for all days after it was created
              end_index = day_range-1 
            end
          end
        end

        # push score into min_scores to be considered for lowest score on each day it can apply for
        (date_index..end_index).each do |i|
          min_scores[r.project_id][i] << sentiment_score
        end if end_index # scores where end_index is set above are considered
      end

      # push score from non_risk_min_score into min_scores
      non_risk_min_score.each do |key, value|
        (0..day_range-1).each do |i|
          min_scores[key][i] << value
        end 
      end
    end

    # set final score of each day by taking min from the innermost array, then round and scale score
    min_scores.each do |key, value|
      (0..day_range-1).each do |i|
        min_scores[key][i] = round_and_scale_score(value[i].sort[0])
      end
    end
    
    min_scores
  end

  def self.count_risks_per_project(array_of_project_ids)
    query = <<-SQL
        SELECT projects.id AS id, 
               projects.name AS name,
               COUNT(*) FILTER (WHERE is_complete = FALSE AND notifications.category = 'Risk') AS open_risks
        FROM projects
        LEFT JOIN notifications
        ON projects.id = notifications.project_id
        WHERE projects.id IN ('#{array_of_project_ids.join("','")}')
        GROUP BY projects.id
      SQL
    result = Project.find_by_sql(query)
  end

  # for risk counts, show every risk regardless of private conversation
  def self.open_risk_count(array_of_project_ids)
    risks_per_project = Project.count_risks_per_project(array_of_project_ids)
    Hash[risks_per_project.map { |p| [p.id, p.open_risks] }]
  end

  def self.current_risk_score(array_of_project_ids, time_zone)
    projects_min_scores = Project.find_min_risk_score_by_day(array_of_project_ids, time_zone, 1)
    Hash[projects_min_scores.map { |pid, scores| [pid, scores[0]] }]
  end

  def current_risk_score(time_zone)
    Project.current_risk_score([self.id], time_zone)[self.id]
  end

  # query to generate Account Relationship Graph from DB entries
  def network_map
    query = <<-SQL 
      WITH email_activities AS 
        (
          SELECT messages ->> 'messageId'::text AS message_id,
                 jsonb_array_elements(messages -> 'from') ->> 'address' AS from,
                 CASE
                   WHEN messages -> 'to' IS NULL THEN NULL
                   ELSE jsonb_array_elements(messages -> 'to') ->> 'address'
                 END AS to,
                 CASE
                   WHEN messages -> 'cc' IS NULL THEN NULL
                   ELSE jsonb_array_elements(messages -> 'cc') ->> 'address'
                 END AS cc
          FROM activities,
          LATERAL jsonb_array_elements(email_messages) messages
          WHERE category IN ('Conversation', 'Meeting')
          AND project_id = '#{self.id}'
          GROUP BY 1,2,3,4
        )
      SELECT "from" AS source,
             "to" AS target,
             COUNT(DISTINCT message_id) AS count
      FROM 
        (SELECT "from", "to", message_id
          FROM email_activities
          UNION ALL
          SELECT "from", cc AS "to", message_id
          FROM email_activities) t
      WHERE "to" IS NOT NULL
      GROUP BY 1,2;
    SQL
    result = Activity.find_by_sql(query)
  end

	def self.find_and_count_activities_by_day(array_of_project_ids, time_zone)
		query = <<-SQL
      WITH time_series as (
        SELECT * 
          from (SELECT generate_series(date (CURRENT_TIMESTAMP AT TIME ZONE '#{time_zone}' - INTERVAL '14 days'), CURRENT_TIMESTAMP AT TIME ZONE '#{time_zone}', INTERVAL '1 day') as days) t1 
                CROSS JOIN 
               (SELECT id as project_id from projects where id in ('#{array_of_project_ids.join("','")}')) t2
       )
      SELECT time_series.project_id as id, date(time_series.days) as date, count(activities.*) as num_activities
      FROM time_series
      LEFT JOIN (SELECT sent_date, project_id 
      					 FROM email_activities_last_14d where project_id in ('#{array_of_project_ids.join("','")}') and sent_date::integer > EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP AT TIME ZONE '#{time_zone}' - INTERVAL '14 days'))
                 ) as activities
        ON activities.project_id = time_series.project_id and date_trunc('day', to_timestamp(activities.sent_date::integer) AT TIME ZONE '#{time_zone}') = time_series.days
      GROUP BY time_series.project_id, days 
      ORDER BY time_series.project_id, days ASC
    SQL

    Project.find_by_sql(query)
  end

  # How Busy Are We? Chart on Home#index
  def self.count_total_activities_by_day(array_of_account_ids, time_zone)
		query = <<-SQL
      WITH time_series AS (
          SELECT * 
          FROM (SELECT generate_series(date(CURRENT_TIMESTAMP AT TIME ZONE '#{time_zone}' - INTERVAL '14 days'), CURRENT_TIMESTAMP AT TIME ZONE '#{time_zone}', INTERVAL '1 day') AS days) t1 
                CROSS JOIN 
               (SELECT id AS project_id 
                FROM projects 
                WHERE account_id IN ('#{array_of_account_ids.join("','")}')) t2
        ), user_activities AS (
          SELECT messages ->> 'messageId'::text AS message_id,
                 messages ->> 'sentDate' AS sent_date,
                 project_id
          FROM activities,
          LATERAL jsonb_array_elements(email_messages) messages
          WHERE category = 'Conversation'
          AND to_timestamp((messages ->> 'sentDate')::integer) BETWEEN (CURRENT_TIMESTAMP AT TIME ZONE '#{time_zone}' - INTERVAL '14 days') AND (CURRENT_TIMESTAMP AT TIME ZONE '#{time_zone}')
          AND project_id IN 
          (
            SELECT id AS project_id 
            FROM projects 
            WHERE account_id IN ('#{array_of_account_ids.join("','")}')
          )
          GROUP BY 1,2,3
        )
      SELECT date(time_series.days) AS date, count(activities.*) AS num_activities
      FROM time_series
      LEFT JOIN user_activities AS activities
      ON activities.project_id = time_series.project_id AND date_trunc('day', to_timestamp(activities.sent_date::integer) AT TIME ZONE '#{time_zone}') = time_series.days
      GROUP BY days 
      ORDER BY days ASC
    SQL

    Project.find_by_sql(query)
  end

	def self.count_activities_by_day(days_ago, array_of_project_ids) # TO-DO: This needs to be deprecated
		metrics = {}
    previous = nil
    arr = []
		days_ago_sql = "(CURRENT_DATE - INTERVAL '#{days_ago-1} days')"

		query = <<-SQL
      WITH time_series as (
        SELECT * 
          FROM (SELECT generate_series(date #{days_ago_sql}, CURRENT_DATE, INTERVAL '1 day') as days) t1 
                CROSS JOIN 
               (SELECT id as project_id from projects where id in ('#{array_of_project_ids.join("','")}')) t2
       )
      SELECT time_series.project_id, time_series.days, count(activities.*) as count_activities
      FROM time_series
      LEFT JOIN (SELECT sent_date, project_id from 
      							(SELECT jsonb_array_elements(email_messages) ->> 'sentDate' as sent_date, project_id 
                    	FROM activities 
                      where project_id in ('#{array_of_project_ids.join("','")}')
                      AND category = 'Conversation'
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

  # Top Active Streams
  def self.find_include_sum_activities(array_of_project_ids, hours_ago_start, hours_ago_end=Date.current)
    hours_ago_end_sql = (hours_ago_end == Date.current) ? 'CURRENT_TIMESTAMP' : "CURRENT_TIMESTAMP - INTERVAL '#{hours_ago_end} hours'"
	  hours_ago_start_sql = "CURRENT_TIMESTAMP - INTERVAL '#{hours_ago_start} hours'"

  	query = <<-SQL
  		SELECT projects.*, count(*) as num_activities from (
				SELECT id, 
							 backend_id, 
							 last_sent_date, 
							 project_id, 
							 jsonb_array_elements(email_messages) ->> 'sentDate' as sent_date 
					from activities 
          where project_id in ('#{array_of_project_ids.join("','")}')
          AND category = 'Conversation'
				) t 
			JOIN projects ON projects.id = t.project_id
      WHERE sent_date::integer between EXTRACT(EPOCH FROM #{hours_ago_start_sql})::integer and EXTRACT(EPOCH FROM #{hours_ago_end_sql})::integer 
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
			project = Project.new(name: (accounts.find {|a| a.domain == p}).name,
													 status: "Active",
													 category: "Opportunity",
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

				# Don't Automatically subscribe to projects created.  This is done in onboarding#confirm_projects
				# project.subscribers.create(user_id: user_id)

				# Project conversations
        Activity.load(get_project_conversations(data, p), project, true, user_id)

        # Load Smart Tasks
        Notification.load(get_project_conversations(data, p), project, false)

        # Load Opportunities
        # 8/30: Temporarily disable this because it gets too noisy during initial onboarding phase
        # Also removing the rake scheduler for this.  Will need to think of a better solution to surface this.
        # Notification.load_opportunity_for_stale_projects(project)
        #Notification.load_opportunity_for_stale_projects(project)

        # Project meetings
				# Activity.load_calendar(get_project_conversations(data, p), project, true, user_id)
        ContextsmithService.load_calendar_from_backend(project, Time.current.to_i, 1.year.ago.to_i, 1000)
			end
		end
	end

  # Top Movers
	def self.calculate_pct_from_prev(projects, projects_prev)
    project_chg_activities = []

		projects.each do |proj|
      proj_prev = projects_prev.find { |p| p.id == proj.id }
      if proj_prev
        proj.pct_from_prev = (((proj.num_activities - proj_prev.num_activities) / proj_prev.num_activities.to_f) * 100).round(1)
        project_chg_activities << proj
      else
        proj.pct_from_prev = 100
        project_chg_activities << proj
      end
    end
    projects_prev.each do |prev|
      if !projects.find { |p| p.id == prev.id }
        prev.pct_from_prev = -100
        project_chg_activities << prev
      end
    end
    return project_chg_activities
	end

	def self.find_stale_projects_30_days
      return project_last_activity_date = Project.all.joins([:activities, "INNER JOIN (SELECT project_id, MAX(last_sent_date_epoch) as last_sent_date_epoch FROM activities where category ='Conversation' group by project_id) AS t 
                                                      ON t.project_id=activities.project_id and t.last_sent_date_epoch=activities.last_sent_date_epoch"])
                                .select("projects.name, projects.id, projects.account_id, t.last_sent_date_epoch as last_sent_date, activities.from")
                                .where("activities.category = 'Conversation' and projects.status='Active' and (t.last_sent_date_epoch::integer + 2592000) < EXTRACT(EPOCH FROM CURRENT_TIMESTAMP)")
                                .group("t.last_sent_date_epoch, activities.from, projects.name, projects.id, projects.account_id")
  end

  def is_stale_project_30_days
  	Project.all.joins([:activities, "INNER JOIN (SELECT project_id, MAX(last_sent_date_epoch) as last_sent_date_epoch FROM activities where category ='Conversation' group by project_id) AS t 
                                                      ON t.project_id=activities.project_id and t.last_sent_date_epoch=activities.last_sent_date_epoch"])
                                .select("projects.name, projects.id, projects.account_id, t.last_sent_date_epoch as last_sent_date, activities.from")
                                .where("activities.category = 'Conversation' and projects.status='Active' and projects.id = '#{self.id}' and (t.last_sent_date_epoch::integer + 2592000) < EXTRACT(EPOCH FROM CURRENT_TIMESTAMP)")
                                .group("t.last_sent_date_epoch, activities.from, projects.name, projects.id, projects.account_id")
  end

  ### method to batch update activities in a project by time (in seconds)
  def timejump(sec)
    self.activities.each { |a| a.timejump(sec) }
  end

  ### method to batch update activities in a project by person
  # finds all instances of email1 and replaces all with email2 in from/to/cc and email_messages for all activities in this project
  # emails should be passed in the format <#Hashie::Mash address: a, personal: p>
  # the email hash can also be created at runtime if either email is just passed as a string
  # for each email passed as a string, must pass an additional string to work as the personal
  def email_replace_all(email1, email2, *personal)
    email1 = Hashie::Mash.new({address: email1, personal: personal.shift}) unless email1.respond_to?(:address) && email1.respond_to?(:personal)
    email2 = Hashie::Mash.new({address: email2, personal: personal.shift}) unless email2.respond_to?(:address) && email2.respond_to?(:personal)

    self.activities.each { |a| a.email_replace_all(email1, email2) }
  end

end