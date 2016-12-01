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

	belongs_to 	:account
  belongs_to  :project_owner, class_name: "User", foreign_key: "owner_id"
  has_many  :subscribers, class_name: "ProjectSubscriber", dependent: :destroy
  has_many  :notifications, dependent: :destroy
  has_many  :notifications_for_email, -> {
    where("is_complete IS FALSE OR (is_complete IS TRUE AND complete_date BETWEEN TIMESTAMP ? AND TIMESTAMP ?)", Time.current.yesterday.midnight.utc, Time.current.yesterday.end_of_day.utc)
    .order(:is_complete, :original_due_date)
  }, class_name: "Notification"

  has_many  :activities, -> { reverse_chronological }, dependent: :destroy
  has_many  :conversations, -> { conversations.reverse_chronological }, class_name: "Activity"
  has_many  :notes, -> { notes.reverse_chronological }, class_name: "Activity"
  has_many  :meetings, -> { meetings.reverse_chronological }, class_name: "Activity"
  has_many  :conversations_for_email, -> {
    from_yesterday.reverse_chronological.conversations
    .select(:category, :title, :from, :to, :cc, :project_id, :last_sent_date, :is_public,
      'jsonb_array_length(email_messages) AS num_messages',
      'email_messages->-1 AS last_msg') }, class_name: "Activity"
  has_many  :other_activities_for_email, -> {
    from_yesterday.reverse_chronological
    .where.not(category: Activity::CATEGORY[:Conversation]) }, class_name: "Activity"

  ### project_members/contacts/users relations have 2 versions
  # v1: only shows confirmed, similar to old logic without project_members.status column
  # v2: "_all" version, ignores status
  has_many  :project_members, -> { confirmed }, dependent: :destroy
  has_many  :project_members_all, class_name: "ProjectMember", dependent: :destroy
  has_many  :contacts, through: "project_members"
  has_many  :contacts_all, through: "project_members_all", source: :contact
  has_many  :users, through: "project_members"
  has_many  :users_all, through: "project_members_all", source: :user

  has_many  :salesforce_opportunities, foreign_key: "contextsmith_project_id", dependent: :nullify

	scope :visible_to, -> (organization_id, user_id) {
		select('DISTINCT(projects.*)')
				.joins([:account, 'LEFT OUTER JOIN project_members ON project_members.project_id = projects.id'])
				.where('accounts.organization_id = ? AND projects.is_confirmed = true AND projects.status = \'Active\' AND (projects.is_public=true OR (projects.is_public=false AND projects.owner_id = ?) OR project_members.user_id = ?)',
							 organization_id, user_id, user_id)
				.group('projects.id')
	}
  scope :owner_of, -> (user_id) {
    select('DISTINCT(projects.*)')
      .where("projects.owner_id = ?", user_id)
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
            complete_index = (r.complete_date.to_i - start_time_sec) / (24*60*60)
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
        ORDER BY open_risks DESC
      SQL
    result = Project.find_by_sql(query)
  end

	def self.find_rag_status_per_project(array_of_project_ids)
		query = <<-SQL
			SELECT project_id,
			rag_score,
			note,
			max(last_sent_date)
			FROM activities
			WHERE project_id IN ('#{array_of_project_ids.join("','")}') AND category='Note' AND rag_score IS NOT NULL
			GROUP BY project_id, note, rag_score, created_at
			ORDER BY created_at ASC;
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

  def self.new_risk_score(array_of_project_ids)
    projects = Project.where(id: array_of_project_ids).group('projects.id')

    # Risk / Engagement Ratio
    p_neg_sentiment_weight = 0.3
    project_engagement = projects.joins(:activities).where(activities: { category: [Activity::CATEGORY[:Conversation], Activity::CATEGORY[:Meeting]] }).sum('jsonb_array_length(activities.email_messages)')
    project_risks = projects.joins("LEFT JOIN notifications ON notifications.project_id = projects.id AND notifications.category = '#{Notification::CATEGORY[:Risk]}'").count('notifications.id')
    project_p_neg_sentiment = project_engagement.merge(project_risks) { |pid, engagement, risks| risks.to_f/engagement*100*p_neg_sentiment_weight }

    # Days Inactive
    inactivity_risk_weight = 0.3
    project_inactivity_risk = projects.joins(:activities).maximum('activities.last_sent_date') # get last_sent_date of last activity for each project
    project_inactivity_risk.each { |pid, last_sent_date| project_inactivity_risk[pid] = last_sent_date.nil? ? 0 : Date.current.mjd - last_sent_date.in_time_zone.to_date.mjd } # convert last_sent_date to days inactive
    project_inactivity_risk.each { |pid, days_inactive| project_inactivity_risk[pid] = [days_inactive/30*25, 100].min*inactivity_risk_weight } # convert days inactive to effect on risk score

    # RAG Status
    rag_score_weight = 0.4
    project_rag_status = Project.current_rag_score(array_of_project_ids)
    project_rag_status.each { |pid, rag_score| project_rag_status[pid] = (3 - rag_score)*50*rag_score_weight }

    # Overall Score
    overall = [project_p_neg_sentiment, project_inactivity_risk, project_rag_status].each_with_object({}) { |oh, nh| nh.merge!(oh) { |pid, h1, h2| h1 + h2 } }
    overall.each { |pid, score| overall[pid] = score.round }
  end

  def new_risk_score
    # Risk / Engagement Ratio
    p_neg_sentiment_weight = 0.3
    engagement = Project.find_include_sum_activities([self.id]).first.num_activities
    risks = self.notifications.risks.count
    percent_neg_sentiment = risks.to_f/engagement*100*p_neg_sentiment_weight

    # Days Inactive
    inactivity_risk_weight = 0.3
    last_sent_date = self.activities.maximum("activities.last_sent_date")
    days_inactive = last_sent_date.nil? ? 0 : Date.current.mjd - last_sent_date.in_time_zone.to_date.mjd
    inactivity_risk = [days_inactive/30*25, 100].min*inactivity_risk_weight

    # RAG Status
    rag_score_weight = 0.4
    rag_status = self.activities.latest_rag_score.first
    rag_score = (rag_status ? (3 - rag_status.rag_score)*50 : 0)*rag_score_weight

    # Overall Score
    (percent_neg_sentiment + inactivity_risk + rag_score).round
  end

	def self.current_rag_score(array_of_project_ids)
		rag_per_project = Project.find_rag_status_per_project(array_of_project_ids)
		Hash[rag_per_project.map { |p| [p.project_id, p.rag_score ]}]
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

  # generate options for Person Filter on Timeline, from activities visible to user with user_email
  def all_involved_people(user_email)
    activities = self.activities.visible_to(user_email).select(:from, :to, :cc, :posted_by).includes(:user)

    people = []
    tempSet = Set.new
    activities.each do |a|
      a.email_addresses.each do |e|
        tempSet.add(e) unless get_domain(e) == 'resources.calendar.google.com' # exclude Google Calendar resource emails
      end
      tempSet.add(a.user.email) if a.user # Add Note Authors
    end

    (User.where(email: tempSet.to_a) + Contact.where(email: tempSet.to_a)).each do |p|
      # exclude duplicate Users/Contacts with the same email
      if tempSet.include? p.email
        if p.first_name.blank? && p.last_name.blank?
          p.first_name  = p.email
        end
        people << p
        tempSet.delete(p.email)
      end
    end

    tempSet.each do |s|
      people << Hashie::Mash.new(first_name: s, email: s)
    end

    people.sort_by {|u| u.first_name.downcase}
  end

  # Used for exploding all activities of a given project without time bound, specifically for time series filter.
  # Subquery is based on email_activities_last_14d view.
  def daily_activities(time_zone)
    query = <<-SQL
      -- Email conversations
      (
      SELECT date(to_timestamp(sent_date::integer) AT TIME ZONE '#{time_zone}') as last_sent_date,
             '#{Activity::CATEGORY[:Conversation]}' as category,
             count(t.*) as activity_count
      FROM
        ( SELECT
            id,
            backend_id,
            last_sent_date,
            project_id,
            is_public,
            jsonb_array_elements(email_messages) ->> 'sentDate' as sent_date,
            jsonb_array_elements(email_messages) -> 'from' as from,
            jsonb_array_elements(email_messages) -> 'to' as to,
            jsonb_array_elements(email_messages) -> 'cc' as cc
          FROM
            activities,
            LATERAL jsonb_array_elements(email_messages) messages
          WHERE
            category = '#{Activity::CATEGORY[:Conversation]}'
            AND
            project_id = '#{self.id}'
          GROUP BY 1,2,3,4,5,6,7,8,9 ) t
      GROUP BY date(to_timestamp(sent_date::integer) AT TIME ZONE '#{time_zone}'), category
      ORDER BY date(to_timestamp(sent_date::integer) AT TIME ZONE '#{time_zone}') ASC
      )
      UNION ALL
      (
      -- Meetings
      SELECT date(last_sent_date AT TIME ZONE '#{time_zone}') as last_sent_date,
            '#{Activity::CATEGORY[:Meeting]}' as category,
            count(*) as activity_count
      FROM activities
      WHERE category = '#{Activity::CATEGORY[:Meeting]}' and project_id = '#{self.id}'
      GROUP BY date(last_sent_date AT TIME ZONE '#{time_zone}'), category
      ORDER BY date(last_sent_date AT TIME ZONE '#{time_zone}')
      )
      UNION ALL
      (
      -- Notes
      SELECT date(last_sent_date AT TIME ZONE '#{time_zone}') as last_sent_date,
            '#{Activity::CATEGORY[:Note]}' as category,
            count(*) as activity_count
      FROM activities
      WHERE category = '#{Activity::CATEGORY[:Note]}' and project_id = '#{self.id}'
      GROUP BY date(last_sent_date AT TIME ZONE '#{time_zone}'), category
      ORDER BY date(last_sent_date AT TIME ZONE '#{time_zone}')
      )
      UNION ALL
      (
      -- JIRA
      SELECT date(last_sent_date AT TIME ZONE '#{time_zone}') as last_sent_date,
            '#{Activity::CATEGORY[:JIRA]}' as category,
            count(*) as activity_count
      FROM activities
      WHERE category = '#{Activity::CATEGORY[:JIRA]}' and project_id = '#{self.id}'
      GROUP BY date(last_sent_date AT TIME ZONE '#{time_zone}'), category
      ORDER BY date(last_sent_date AT TIME ZONE '#{time_zone}')
      )
      UNION ALL
      (
      -- Salesforce
      SELECT date(last_sent_date AT TIME ZONE '#{time_zone}') as last_sent_date,
            '#{Activity::CATEGORY[:Salesforce]}' as category,
            count(*) as activity_count
      FROM activities
      WHERE category = '#{Activity::CATEGORY[:Salesforce]}' and project_id = '#{self.id}'
      GROUP BY date(last_sent_date AT TIME ZONE '#{time_zone}'), category
      ORDER BY date(last_sent_date AT TIME ZONE '#{time_zone}')
      )
      UNION ALL
      (
      -- Zendesk
      SELECT date(last_sent_date AT TIME ZONE '#{time_zone}') as last_sent_date,
            '#{Activity::CATEGORY[:Zendesk]}' as category,
            count(*) as activity_count
      FROM activities
      WHERE category = '#{Activity::CATEGORY[:Zendesk]}' and project_id = '#{self.id}'
      GROUP BY date(last_sent_date AT TIME ZONE '#{time_zone}'), category
      ORDER BY date(last_sent_date AT TIME ZONE '#{time_zone}')
      )
    SQL

    Activity.find_by_sql(query)
  end

  # This is the SQL query that gets the daily activities over the last x days, where x is 1-14
  # Used for time bounded time series
  def daily_activities_last_x_days(time_zone, days_ago=14)
    query = <<-SQL
      -- This controls the dates return by the query
      WITH time_series as (
        SELECT '#{self.id}'::uuid as project_id, generate_series(date (CURRENT_TIMESTAMP AT TIME ZONE '#{time_zone}' - INTERVAL '#{days_ago} days'), date(CURRENT_TIMESTAMP AT TIME ZONE '#{time_zone}' - INTERVAL '1 day'), INTERVAL '1 day') as days
       )
      (
      -- Email Conversation using emails_activities_last_14d view
      SELECT time_series.project_id as project_id, date(time_series.days) as last_sent_date, '#{Activity::CATEGORY[:Conversation]}' as category, count(activities.*) as num_activities
      FROM time_series
      LEFT JOIN (SELECT sent_date, project_id
                 FROM email_activities_last_14d where project_id = '#{self.id}' and EXTRACT(EPOCH FROM (to_timestamp(sent_date::integer) AT TIME ZONE '#{time_zone}')) > EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP AT TIME ZONE '#{time_zone}' - INTERVAL '#{days_ago} days'))
                 ) as activities
        ON activities.project_id = time_series.project_id and date_trunc('day', to_timestamp(activities.sent_date::integer) AT TIME ZONE '#{time_zone}') = time_series.days
      GROUP BY time_series.project_id, days, category
      ORDER BY time_series.project_id, days ASC
      )
      UNION ALL
      (
      -- Meetings directly from actvities table
      SELECT time_series.project_id as project_id, date(time_series.days) as last_sent_date, '#{Activity::CATEGORY[:Meeting]}' as category, count(meetings.*) as num_activities
      FROM time_series
      LEFT JOIN (SELECT last_sent_date as sent_date, project_id
                  FROM activities where category = '#{Activity::CATEGORY[:Meeting]}' and project_id = '#{self.id}' and EXTRACT(EPOCH FROM last_sent_date AT TIME ZONE '#{time_zone}') > EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP AT TIME ZONE '#{time_zone}' - INTERVAL '#{days_ago} days'))
                ) as meetings
        ON meetings.project_id = time_series.project_id and date_trunc('day', meetings.sent_date AT TIME ZONE '#{time_zone}') = time_series.days
      GROUP BY time_series.project_id, days, category
      ORDER BY time_series.project_id, days ASC
      )
      UNION ALL
      (
      -- Meetings directly from actvities table
      SELECT time_series.project_id as project_id, date(time_series.days) as last_sent_date, '#{Activity::CATEGORY[:Note]}' as category, count(meetings.*) as num_activities
      FROM time_series
      LEFT JOIN (SELECT last_sent_date as sent_date, project_id
                  FROM activities where category = '#{Activity::CATEGORY[:Note]}' and project_id = '#{self.id}' and EXTRACT(EPOCH FROM last_sent_date AT TIME ZONE '#{time_zone}') > EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP AT TIME ZONE '#{time_zone}' - INTERVAL '#{days_ago} days'))
                ) as meetings
        ON meetings.project_id = time_series.project_id and date_trunc('day', meetings.sent_date AT TIME ZONE '#{time_zone}') = time_series.days
      GROUP BY time_series.project_id, days, category
      ORDER BY time_series.project_id, days ASC
      )
      UNION ALL
      (
      -- JIRA directly from actvities table
      SELECT time_series.project_id as project_id, date(time_series.days) as last_sent_date, '#{Activity::CATEGORY[:JIRA]}' as category, count(meetings.*) as num_activities
      FROM time_series
      LEFT JOIN (SELECT last_sent_date as sent_date, project_id
                  FROM activities where category = '#{Activity::CATEGORY[:JIRA]}' and project_id = '#{self.id}' and EXTRACT(EPOCH FROM last_sent_date AT TIME ZONE '#{time_zone}') > EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP AT TIME ZONE '#{time_zone}' - INTERVAL '#{days_ago} days'))
                ) as meetings
        ON meetings.project_id = time_series.project_id and date_trunc('day', meetings.sent_date AT TIME ZONE '#{time_zone}') = time_series.days
      GROUP BY time_series.project_id, days, category
      ORDER BY time_series.project_id, days ASC
      )
      UNION ALL
      (
      -- Salesforce directly from actvities table
      SELECT time_series.project_id as project_id, date(time_series.days) as last_sent_date, '#{Activity::CATEGORY[:Salesforce]}' as category, count(meetings.*) as num_activities
      FROM time_series
      LEFT JOIN (SELECT last_sent_date as sent_date, project_id
                  FROM activities where category = '#{Activity::CATEGORY[:Salesforce]}' and project_id = '#{self.id}' and EXTRACT(EPOCH FROM last_sent_date AT TIME ZONE '#{time_zone}') > EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP AT TIME ZONE '#{time_zone}' - INTERVAL '#{days_ago} days'))
                ) as meetings
        ON meetings.project_id = time_series.project_id and date_trunc('day', meetings.sent_date AT TIME ZONE '#{time_zone}') = time_series.days
      GROUP BY time_series.project_id, days, category
      ORDER BY time_series.project_id, days ASC
      )
      UNION ALL
      (
      -- Zendesk directly from actvities table
      SELECT time_series.project_id as project_id, date(time_series.days) as last_sent_date, '#{Activity::CATEGORY[:Zendesk]}' as category, count(meetings.*) as num_activities
      FROM time_series
      LEFT JOIN (SELECT last_sent_date as sent_date, project_id
                  FROM activities where category = '#{Activity::CATEGORY[:Zendesk]}' and project_id = '#{self.id}' and EXTRACT(EPOCH FROM last_sent_date AT TIME ZONE '#{time_zone}') > EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP AT TIME ZONE '#{time_zone}' - INTERVAL '#{days_ago} days'))
                ) as meetings
        ON meetings.project_id = time_series.project_id and date_trunc('day', meetings.sent_date AT TIME ZONE '#{time_zone}') = time_series.days
      GROUP BY time_series.project_id, days, category
      ORDER BY time_series.project_id, days ASC
      )
    SQL

    Activity.find_by_sql(query)
  end

  # This is the SQL query to get daily activities for multiple projects.  TO DO: get rid of cross join
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

    Activity.find_by_sql(query)
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

# TO-DO: This needs to be deprecated.  Use daily_activities_last_x_days.
	def self.count_activities_by_day(days_ago, array_of_project_ids)
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

  # Top Active Streams/Engagement Last 7d
  def self.find_include_sum_activities(array_of_project_ids, hours_ago_start=false, hours_ago_end=0)
    hours_ago_end = hours_ago_end.hours.ago.to_i
    hours_ago_start = hours_ago_start ? hours_ago_start.hours.ago.to_i : 0

    query = <<-SQL
      SELECT projects.*, COUNT(*) AS num_activities
      FROM (
        SELECT id,
               category,
               project_id,
               last_sent_date,
               jsonb_array_elements(email_messages) ->> 'sentDate' AS sent_date
        FROM activities
        WHERE project_id IN ('#{array_of_project_ids.join("','")}')
        ) t
      JOIN projects ON projects.id = t.project_id
      WHERE (t.category = '#{Activity::CATEGORY[:Conversation]}' AND (sent_date::integer BETWEEN #{hours_ago_start} AND #{hours_ago_end}))
      OR (t.category = '#{Activity::CATEGORY[:Meeting]}' AND (EXTRACT(EPOCH FROM last_sent_date) BETWEEN #{hours_ago_start} AND #{hours_ago_end}))
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
  # finds all instances of email1 and replaces all with email2 in from/to/cc and email_messages for the activity
  # email1 should be passed as a string, e.g. 'klu@contextsmith.com'
  # email 2 should be passed in the format <#Hashie::Mash address: a, personal: p>
  # the email2 hash can also be created at runtime if it is just passed as a string, then passing a personal is recommended
  def email_replace_all(email1, email2, personal=nil)
    email2 = Hashie::Mash.new({address: email2, personal: personal}) unless email2.respond_to?(:address) && email2.respond_to?(:personal)
    self.activities.each { |a| a.email_replace_all(email1, email2) }
  end

end
