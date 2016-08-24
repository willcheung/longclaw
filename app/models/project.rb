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
	belongs_to	:project_owner, class_name: "User", foreign_key: "owner_id"
	has_many	:project_members, dependent: :destroy
	has_many	:activities, -> { order "last_sent_date DESC" }, dependent: :destroy
	has_many	:contacts, through: "project_members"
	has_many	:users, through: "project_members"
	has_many  :subscribers, class_name: "ProjectSubscriber", dependent: :destroy
  has_many  :notifications, dependent: :destroy

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

  def self.find_min_risk_score_by_day(array_of_project_ids, time_zone, test=false, day_range=14)
    # Calculate time since epoch in seconds for today at 23:59:59 based on current user time zone
    # current_time = Time.zone.now
    # current_time_int = Time.zone.local(current_time.year, current_time.month, current_time.day,23,59,59).utc.to_i
    current_time_int = Time.current.end_of_day.utc.to_i
    start_time_sec = (day_range-1).days.ago.midnight.utc.to_i

    if test
      current_time_int = Time.zone.local(2014,9,21,23,59,59).utc.to_i
      start_time_sec = current_time_int - 60*60*24*day_range + 1
    end

    query = <<-SQL
        SELECT messages->>'sentimentItems' as sentiment_item,
               messages ->> 'sentDate' as sentdate,
               activities.project_id as project_id,
               messages ->> 'messageId' AS message_id,
               activities.backend_id AS conversation_id
        FROM activities, LATERAL jsonb_array_elements(email_messages) messages
        WHERE category = 'Conversation'
        AND messages->>'sentimentItems' is NOT NULL 
        AND project_id IN ('#{array_of_project_ids.join("','")}')
        AND (messages ->> 'sentDate')::integer > #{start_time_sec}
      SQL
    result= Activity.find_by_sql(query)

    project_min_score = Hash.new()
    project_min_temp = Hash.new()

    array_of_project_ids.each do |pid|
      project_min_score[pid] = Array.new(day_range,nil) 
      project_min_temp[pid] = Array.new(day_range, nil)
    end
    
    if !result.nil?
      result.each do|r|          
        sentiment_json = JSON.parse(r.sentiment_item)
      
        #reverse
        # current_time - sent_date = seconds since sent_date
        # 24*60*60 = seconds in a day
        # (current_time - sent_date)/24/60/60 = days since sent_date
        # 13 - ( days since sent_date ) = days since sent_date from 13 days ago
        temp_date_index = (day_range-1) - ((current_time_int - r.sentdate.to_i) / (24*60*60))

       
        # for each score, it will show up from the first appearing date to the current date
        # if that notification is completed(could be uncomplete or no notification if score is less than 95%)
        # pop the score starting from the complete date till current date
        # so for each day we have the correct possible score values
        for i in temp_date_index..day_range-1
          if project_min_temp[r.project_id][i].nil?
            project_min_temp[r.project_id][i] = [sentiment_json[0]['score'].to_f]
          else
            project_min_temp[r.project_id][i].push(sentiment_json[0]['score'].to_f)
          end 
        end
        
        target = Notification.find_by(category: Notification::CATEGORY[:Risk], project_id: r.project_id, conversation_id: r.conversation_id, message_id: r.message_id, is_complete: true)
        if !target.nil?
          index = (day_range-1) - ((current_time_int - target.complete_date.to_i) / (24*60*60))
          if temp_date_index<=index
            for i in index..day_range-1
              project_min_temp[r.project_id][i].pop()
            end
          end
        end 
      end
    end

    # set min score of each day
    project_min_temp.each do |key, value|
      for i in 0..day_range-1
        if !value[i].nil? and value[i].length>0
          value[i] = value[i].sort {|x, y| (x.to_s[0,7].to_f) <=> (y.to_s[0,7].to_f) }
          project_min_score[key][i] = value[i][0]
        end
      end
    end     

    # scale score
    project_min_score.each do |key, value|
      for i in 0..day_range-1
        if !value[i].nil?
          value[i] = round_and_scale_score(value[i])
        end
      end
    end
    
    return project_min_score
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
    project_open_risk_count = Hash[array_of_project_ids.map { |pid| [pid, 0] }]

    array_of_project_ids.each do |id|
      project_open_risk_count[id] = Notification.where(is_complete: false, category: Notification::CATEGORY[:Risk], project_id: id).length
    end

    return project_open_risk_count

  end

  def self.current_risk_score(array_of_project_ids)
    # results hash, initialize with 0 for every project
    project_current_score = Hash[array_of_project_ids.map { |pid| [pid, 0] }]
    # get every risk score for all projects in array of project ids
    query = <<-SQL
      SELECT messages->>'sentimentItems' AS sentiment_item,
             messages ->> 'sentDate' AS sent_date,
             activities.project_id AS project_id,
             messages ->> 'messageId' AS message_id,
             activities.backend_id AS backend_id
      FROM activities, LATERAL jsonb_array_elements(email_messages) messages
      WHERE category = 'Conversation' 
      AND messages->>'sentimentItems' IS NOT NULL
      AND project_id IN ('#{array_of_project_ids.join("','")}')
      ORDER BY (messages ->> 'sentDate')::integer DESC
    SQL
    result = Activity.find_by_sql(query)
    return project_current_score if result.blank?

    open_risks = Notification.where(category: Notification::CATEGORY[:Risk], is_complete: false)
    completed_risks = Notification.where(category: Notification::CATEGORY[:Risk], is_complete: true)

    scores_by_pid = result.group_by { |a| a.project_id }
    scores_by_pid.each do |pid, scores|
      score = 0
      pid_open_risks = open_risks.where(project_id: pid)
      if pid_open_risks.present?
        # get every risk score from open risks
        open_risk_scores = scores.select do |a|
          pid_open_risks.any? { |r| r.conversation_id == a.backend_id && r.message_id == a.message_id }
        end
        # Risk notification may refer to emails that are not found in db for some reason, open_risk_scores may be empty
        if open_risk_scores.present?
          # get min score of all open risk scores
          score = min_risk_score(open_risk_scores)
        end
      end

      # if score for this pid is still 0 after calculation from open risks
      if score == 0
        # get min score from last day that has risk score, excluding completed risks
        pid_completed_risks = completed_risks.where(project_id: pid)
        scores.reject! do |a|
          pid_completed_risks.any? { |r| r.conversation_id == a.backend_id && r.message_id == a.message_id }
        end
        last_sent_date = Time.zone.at(scores.first.sent_date.to_i).to_date
        scores.select! do |a|
          Time.zone.at(a.sent_date.to_i).to_date == last_sent_date
        end
        score = min_risk_score(scores)
      end
      project_current_score[pid] = round_and_scale_score(score)
    end
      
    project_current_score
  end

  def current_risk_score
    # get every risk score for this project
    query = <<-SQL
      SELECT messages->>'sentimentItems' AS sentiment_item,
             messages ->> 'sentDate' AS sent_date,
             messages ->> 'messageId' AS message_id,
             backend_id
      FROM activities, LATERAL jsonb_array_elements(email_messages) messages
      WHERE category = 'Conversation'
      AND messages->>'sentimentItems' IS NOT NULL
      AND project_id = '#{self.id}'
      ORDER BY (messages ->> 'sentDate')::integer DESC
    SQL
    result = Activity.find_by_sql(query)
    # if no risk scores found, return score of 0
    return 0 if result.blank?

    open_risks = notifications.where(category: Notification::CATEGORY[:Risk], is_complete: false)
    if open_risks.present?
      # get every risk score from open risks
      open_risk_scores = result.select do |a|
        open_risks.any? { |r| r.conversation_id == a.backend_id && r.message_id == a.message_id }
      end
      # Risk notification may refer to emails that are not found in db for some reason, open_risk_scores may be empty
      if open_risk_scores.present?
        # get min score of all open risk scores
        score = min_risk_score(open_risk_scores)
      end
    end

    # if no score calculated from open risks
    if score.nil?
      # get min score from last day that has risk score, excluding completed risks
      completed_risks = notifications.where(category: Notification::CATEGORY[:Risk], is_complete: true)
      result.reject! do |a|
        completed_risks.any? { |r| r.conversation_id == a.backend_id && r.message_id == a.message_id }
      end
      last_sent_date = Time.zone.at(result.first.sent_date.to_i).to_date
      result.select! do |a|
        Time.zone.at(a.sent_date.to_i).to_date == last_sent_date
      end
      score = min_risk_score(result)
    end

    round_and_scale_score(score)
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
        Notification.load_opportunity_for_stale_projects(project)

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