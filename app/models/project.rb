# == Schema Information
#
# Table name: projects
#
#  id                  :uuid             not null, primary key
#  name                :string           default(""), not null
#  account_id          :uuid
#  project_code        :string
#  is_public           :boolean          default(TRUE)
#  status              :string           default("Active")
#  description         :text
#  start_date          :date
#  end_date            :date
#  budgeted_hours      :integer
#  created_by          :uuid
#  updated_by          :uuid
#  owner_id            :uuid
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  is_confirmed        :boolean
#  category            :string           default("Implementation")
#  deleted_at          :datetime
#  renewal_date        :date
#  contract_start_date :date
#  contract_end_date   :date
#  contract_arr        :decimal(14, 2)
#  contract_mrr        :decimal(12, 2)
#  renewal_count       :integer
#  has_case_study      :boolean          default(FALSE), not null
#  is_referenceable    :boolean          default(FALSE), not null
#
# Indexes
#
#  index_projects_on_account_id  (account_id)
#  index_projects_on_deleted_at  (deleted_at)
#

include Utils
include ContextSmithParser

class Project < ActiveRecord::Base
  after_create  :create_custom_fields

  belongs_to  :account
  belongs_to  :project_owner, class_name: "User", foreign_key: "owner_id"
  has_many  :subscribers, class_name: "ProjectSubscriber", dependent: :destroy
  has_many  :notifications, dependent: :destroy
  has_many  :notifications_for_daily_email, -> {
    where("is_complete IS FALSE OR (is_complete IS TRUE AND complete_date BETWEEN TIMESTAMP ? AND TIMESTAMP ?)", Time.current.yesterday.midnight.utc, Time.current.yesterday.end_of_day.utc)
    .order(:is_complete, :original_due_date)
  }, class_name: "Notification"
  #has_many  :notifications_for_weekly_email, -> {
  #  where("is_complete IS FALSE OR (is_complete IS TRUE AND complete_date BETWEEN TIMESTAMP ? AND TIMESTAMP ?)", Time.current.yesterday.midnight.utc - 1.weeks, Time.current.yesterday.end_of_day.utc)
  #  .order(:is_complete, :original_due_date)
  #}, class_name: "Notification"

  has_many  :activities, -> { reverse_chronological }, dependent: :destroy
  has_many  :conversations, -> { conversations.reverse_chronological }, class_name: "Activity"
  has_many  :notes, -> { notes.reverse_chronological }, class_name: "Activity"
  has_many  :meetings, -> { meetings.reverse_chronological }, class_name: "Activity"
  has_many  :conversations_for_daily_email, -> {
    from_yesterday.reverse_chronological.conversations
    .select(:category, :title, :from, :to, :cc, :project_id, :last_sent_date, :is_public,
      'jsonb_array_length(email_messages) AS num_messages',
      'email_messages->-1 AS last_msg') }, class_name: "Activity"
  #has_many  :conversations_for_weekly_email, -> {
  #  from_lastweek.reverse_chronological.conversations
  #  .select(:category, :title, :from, :to, :cc, :project_id, :last_sent_date, :is_public,
  #    'jsonb_array_length(email_messages) AS num_messages',
  #    'email_messages->-1 AS last_msg') }, class_name: "Activity"
  has_many  :other_activities_for_daily_email, -> {
    from_yesterday.reverse_chronological
    .where.not(category: Activity::CATEGORY[:Conversation]) }, class_name: "Activity"
  #has_many  :other_activities_for_weekly_email, -> {
  #  from_lastweek.reverse_chronological
  #  .where.not(category: Activity::CATEGORY[:Conversation]) }, class_name: "Activity"

  ### project_members/contacts/users relations have 2 versions
  # v1: only shows confirmed, similar to old logic without project_members.status column
  # v2: "_all" version, ignores status
  has_many  :project_members, -> { confirmed }, dependent: :destroy, class_name: 'ProjectMember'
  has_many  :project_members_all, class_name: "ProjectMember", dependent: :destroy
  has_many  :contacts, through: "project_members"
  has_many  :contacts_all, through: "project_members_all", source: :contact
  has_many  :users, through: "project_members"
  has_many  :users_all, through: "project_members_all", source: :user

  has_one  :salesforce_opportunity, foreign_key: "contextsmith_project_id", dependent: :nullify
  has_many :custom_fields, as: :customizable, foreign_key: "customizable_uuid", dependent: :destroy

  # TODO: Combine visible_to and visible_to_admin scopes for a general "role" checker
  scope :visible_to, -> (organization_id, user_id) {
    select('DISTINCT(projects.*)')
        .joins([:account, 'LEFT OUTER JOIN project_members ON project_members.project_id = projects.id'])
        .where('accounts.organization_id = ? AND projects.is_confirmed = true AND projects.status = \'Active\' AND (projects.is_public=true OR (projects.is_public=false AND projects.owner_id = ?) OR project_members.user_id = ?)',
               organization_id, user_id, user_id)
        .group('projects.id')
  }
  scope :visible_to_admin, -> (organization_id) {
    select('DISTINCT(projects.*)')
        .joins(:account)
        .where('accounts.organization_id = ?', organization_id)
        .group('projects.id')
  }
  scope :owner_of, -> (user_id) {
    select('DISTINCT(projects.*)')
      .where("projects.owner_id = ?", user_id)
  }

  # Only using this for Daily Summaries
  scope :following_daily, -> (user_id) {
    joins("INNER JOIN project_subscribers ON project_subscribers.project_id = projects.id")
    .where("project_subscribers.user_id = ? AND project_subscribers.daily IS TRUE", user_id)
  }
  # Only using this for Weekly Summaries
  scope :following_weekly, -> (user_id) {
    joins("INNER JOIN project_subscribers ON project_subscribers.project_id = projects.id")
    .where("project_subscribers.user_id = ? AND project_subscribers.weekly IS TRUE", user_id)
  }
  
  scope :is_active, -> {where("projects.status = 'Active'")}
  scope :is_confirmed, -> {where("projects.is_confirmed = true")}

  validates :name, presence: true, uniqueness: { scope: [:account, :project_owner, :is_confirmed], message: "There's already a stream with the same name." }
  validates :budgeted_hours, numericality: { only_integer: true, allow_blank: true }

  STATUS = ["Active", "Completed", "On Hold", "Cancelled", "Archived"]
  CATEGORY = { Adoption: 'Adoption', Expansion: 'Expansion', Implementation: 'Implementation', Onboarding: 'Onboarding', Opportunity: 'Opportunity', Pilot: 'Pilot', Support: 'Support', Other: 'Other' }
  RAGSTATUS = { Red: "Red", Amber: "Amber", Green: "Green" }

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
        AND notifications.category = '#{Notification::CATEGORY[:Alert]}'
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
        score = value[i].sort[0]
        min_scores[key][i] = scale_sentiment_score(score)
      end
    end

    min_scores
  end

  def self.count_tasks_per_project(array_of_project_ids)
    query = <<-SQL
        SELECT projects.id AS id,
               projects.name AS name,
               COUNT(*) FILTER (WHERE is_complete = FALSE ) AS open_risks
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
      GROUP BY project_id, note, rag_score, last_sent_date
      ORDER BY last_sent_date ASC;
    SQL
    result = Project.find_by_sql(query)
  end

  # for risk counts, show every risk regardless of private conversation
  def self.open_risk_count(array_of_project_ids)
    risks_per_project = Project.count_tasks_per_project(array_of_project_ids)
    Hash[risks_per_project.map { |p| [p.id, p.open_risks] }]
  end

  def self.current_risk_score(array_of_project_ids, time_zone)
    projects_min_scores = Project.find_min_risk_score_by_day(array_of_project_ids, time_zone, 1)
    Hash[projects_min_scores.map { |pid, scores| [pid, scores[0]] }]
  end

  def current_risk_score(time_zone)
    Project.current_risk_score([self.id], time_zone)[self.id]
  end

  def self.new_risk_score(array_of_project_ids, time_zone)
    projects = Project.where(id: array_of_project_ids).group('projects.id')

    return [] if projects.empty?   # quit early if there are no projects

    risk_settings = RiskSetting.where(level: projects.first.account.organization)

    # Risk / Engagement Ratio
    sentiment_setting = risk_settings.find { |rs| rs.metric == RiskSetting::METRIC[:NegSentiment] }
    pct_neg_sentiment_setting = risk_settings.find { |rs| rs.metric == RiskSetting::METRIC[:PctNegSentiment] }
    project_engagement = projects.joins(:activities).where(activities: { category: Activity::CATEGORY[:Conversation] }).sum('jsonb_array_length(activities.email_messages)')
    project_risks = projects.includes(:activities).where(activities: { category: Activity::CATEGORY[:Conversation] }).group('activities.id')
    project_p_neg_sentiment = project_risks.each_with_object({}) do |p, result|
      risks = p.activities.select("(jsonb_array_elements(jsonb_array_elements(email_messages)->'sentimentItems')->>'score')::float AS sentiment_score")
        .map { |a| scale_sentiment_score(a.sentiment_score) }.select{ |score| score > sentiment_setting.high_threshold }.count
      result[p.id] = calculate_score_by_setting(risks.to_f/project_engagement[p.id], pct_neg_sentiment_setting)
    end
      

    # Days Inactive
    days_inactive_setting = risk_settings.find { |rs| rs.metric == RiskSetting::METRIC[:DaysInactive] }
    project_inactivity_risk = projects.joins(:activities).where.not(activities: { category: [Activity::CATEGORY[:Note], Activity::CATEGORY[:Alert]] }).maximum('activities.last_sent_date') # get last_sent_date of last activity for each project
    project_inactivity_risk.each { |pid, last_sent_date| project_inactivity_risk[pid] = Time.current.in_time_zone(time_zone).to_date.mjd - last_sent_date.in_time_zone(time_zone).to_date.mjd } # convert last_sent_date to days inactive
    project_inactivity_risk.each { |pid, days_inactive| project_inactivity_risk[pid] = calculate_score_by_setting(days_inactive, days_inactive_setting) } # convert days inactive to effect on risk score

    # RAG Status
    rag_status_setting = risk_settings.find { |rs| rs.metric == RiskSetting::METRIC[:RAGStatus] }
    project_rag_status = Project.current_rag_score(array_of_project_ids)
    project_rag_status.each { |pid, rag_score| project_rag_status[pid] = calculate_score_by_setting(rag_score, rag_status_setting) }

    # Overall Score
    overall = [project_p_neg_sentiment, project_inactivity_risk, project_rag_status].each_with_object({}) { |oh, nh| nh.merge!(oh) { |pid, h1, h2| h1 + h2 } }
    overall.each { |pid, score| overall[pid] = score.round }
  end

  def new_risk_score(time_zone)
    risk_settings = RiskSetting.where(level: self.account.organization)
    # Risk / Engagement Ratio
    sentiment_setting = risk_settings.find { |rs| rs.metric == RiskSetting::METRIC[:NegSentiment] }
    pct_neg_sentiment_setting = risk_settings.find { |rs| rs.metric == RiskSetting::METRIC[:PctNegSentiment] }
    engagement = self.conversations.sum('jsonb_array_length(activities.email_messages)')
    if engagement.zero?
      percent_neg_sentiment = 0
    else
      risks = self.conversations.select("(jsonb_array_elements(jsonb_array_elements(email_messages)->'sentimentItems')->>'score')::float AS sentiment_score")
        .map { |a| scale_sentiment_score(a.sentiment_score) }.select { |score| score > sentiment_setting.high_threshold }.count
      percent_neg_sentiment = Project.calculate_score_by_setting(risks.to_f/engagement, pct_neg_sentiment_setting)
    end

    # Days Inactive
    days_inactive_setting = risk_settings.find { |rs| rs.metric == RiskSetting::METRIC[:DaysInactive] }
    last_sent_date = self.activities.where.not(category: [Activity::CATEGORY[:Note], Activity::CATEGORY[:Alert]]).maximum(:last_sent_date)
    days_inactive = last_sent_date.nil? ? 0 : Time.current.in_time_zone(time_zone).to_date.mjd - last_sent_date.in_time_zone(time_zone).to_date.mjd
    inactivity_risk = Project.calculate_score_by_setting(days_inactive, days_inactive_setting)

    # RAG Status
    rag_score_setting = risk_settings.find { |rs| rs.metric == RiskSetting::METRIC[:RAGStatus] }
    rag_status = self.activities.latest_rag_score.first
    rag_score = (rag_status ? Project.calculate_score_by_setting(rag_status.rag_score, rag_score_setting) : 0)

    # Overall Score
    (percent_neg_sentiment + inactivity_risk + rag_score).round
  end

  def new_risk_score_trend(time_zone, day_range=14)
    risk_settings = RiskSetting.where(level: self.account.organization)
    
    # Risk / Engagement Ratio
    sentiment_setting = risk_settings.find { |rs| rs.metric == RiskSetting::METRIC[:NegSentiment] }
    pct_neg_sentiment_setting = risk_settings.find { |rs| rs.metric == RiskSetting::METRIC[:PctNegSentiment] }
    total_engagement = self.conversations
    if total_engagement.count.zero?
      pct_neg_sentiment_by_day = Array.new(day_range, 0)
    else
      pct_neg_sentiment_by_day = ((day_range - 1).days.ago.in_time_zone(time_zone).to_date..Time.current.in_time_zone(time_zone).to_date).map do |date|
        engagement = total_engagement.where(last_sent_date: Time.at(0)..date).sum('jsonb_array_length(activities.email_messages)')
        if engagement.zero?
          0
        else
          risks = total_engagement.where(last_sent_date: Time.at(0)..date)
            .select("(jsonb_array_elements(jsonb_array_elements(email_messages)->'sentimentItems')->>'score')::float AS sentiment_score")
            .map { |a| scale_sentiment_score(a.sentiment_score) }.select { |score| score > sentiment_setting.high_threshold }.count
          Project.calculate_score_by_setting(risks.to_f/engagement, pct_neg_sentiment_setting)
        end
      end
    end
    
    # Days Inactive
    days_inactive_setting = risk_settings.find { |rs| rs.metric == RiskSetting::METRIC[:DaysInactive] }
    activity_dates = self.activities.where.not(category: [Activity::CATEGORY[:Note], Activity::CATEGORY[:Alert]]).pluck(:last_sent_date).map { |d| d.in_time_zone(time_zone).to_date }.to_set
    days_inactive_by_day = ((day_range - 1).days.ago.in_time_zone(time_zone).to_date..Time.current.in_time_zone(time_zone).to_date).map do |date|
      last_active_date = activity_dates.drop_while { |d| d > date }.first
      days_inactive = last_active_date.nil? ? 0 : date.mjd - last_active_date.mjd
      Project.calculate_score_by_setting(days_inactive, days_inactive_setting)
    end

    # RAG Status
    rag_score_setting = risk_settings.find { |rs| rs.metric == RiskSetting::METRIC[:RAGStatus] }
    rag_score_by_day = Array.new(day_range, 3) # "Green" status by default if no previous set status
    rag_scores = self.activities.latest_rag_score.reverse_order
    rag_scores.each do |rag|
      date_index = [day_range - 1 - Time.current.in_time_zone(time_zone).to_date.mjd + rag.last_sent_date.in_time_zone(time_zone).to_date.mjd, 0].max
      (date_index...day_range).each { |i| rag_score_by_day[i] = rag.rag_score }
    end
    rag_score_by_day.map! { |score| Project.calculate_score_by_setting(score, rag_score_setting) }

    [rag_score_by_day, days_inactive_by_day, pct_neg_sentiment_by_day].transpose.map(&:sum)
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
      UNION ALL
      (
      -- Alert
      SELECT date(last_sent_date AT TIME ZONE '#{time_zone}') as last_sent_date,
            '#{Activity::CATEGORY[:Alert]}' as category,
            count(*) as activity_count
      FROM activities
      WHERE category = '#{Activity::CATEGORY[:Alert]}' and project_id = '#{self.id}'
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

        # Upsert project conversations.
        Activity.load(get_project_conversations(data, p), project, true, user_id)

        # Upsert/load Smart Tasks.
        #Notification.load(get_project_conversations(data, p), project, false)

        # Load Opportunities
        # 8/30: Temporarily disable this because it gets too noisy during initial onboarding phase
        # Also removing the rake scheduler for this.  Will need to think of a better solution to surface this.
        # Notification.load_opportunity_for_stale_projects(project)

        # Upsert project meetings.
        ContextsmithService.load_calendar_from_backend(project, 1000)
      end
    end
  end  #End: self.create_from_clusters()

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

  # Retreives Alerts in the project's Notifications with a created_at date within the specified range.
  # days_ago_start: start of created_at date range in number of days ago from today (default:"earliest date possible")
  # days_ago_end: end of created_at date range in number of days ago from today, non-inclusive! (default:"yesterday")
  def get_alerts_in_range(time_zone, days_ago_start=nil, days_ago_end=0)
    if (days_ago_start.nil?)
      self.notifications.risks.where("created_at < ? ", (days_ago_end).days.ago.in_time_zone(time_zone).to_date)
    else
      self.notifications.risks.where(created_at: (days_ago_start).days.ago.in_time_zone(time_zone).to_date..(days_ago_end).days.ago.in_time_zone(time_zone).to_date)
    end
  end

  # Updates all mapped custom fields of a single SF opportunity -> CS stream
  def self.load_salesforce_fields(salesforce_client, project_id, sfdc_opportunity_id, stream_custom_fields)
    unless (salesforce_client.nil? or project_id.nil? or sfdc_opportunity_id.nil? or stream_custom_fields.nil? or stream_custom_fields.empty?)
      stream_custom_field_names = []
      stream_custom_fields.each { |cf| stream_custom_field_names << cf.salesforce_field }

      query_statement = "SELECT " + stream_custom_field_names.join(", ") + " FROM Opportunity WHERE Id = '#{sfdc_opportunity_id}' LIMIT 1"
      sObjects_result = SalesforceService.query_salesforce(salesforce_client, query_statement)

      unless sObjects_result.nil?
        sObj = sObjects_result.first
        stream_custom_fields.each do |cf|
          #csfield = CustomField.find_by(custom_fields_metadata_id: cf.id, customizable_uuid: project_id)
          #print "----> CS_fieldname=\"", cf.name, "\" SF_fieldname=\"", cf.salesforce_field, "\"\n"
          #print "   .. CS_fieldvalue=\"", csfield.value, "\" SF_fieldvalue=\"", sObj[cf.salesforce_field], "\"\n"
          CustomField.find_by(custom_fields_metadata_id: cf.id, customizable_uuid: project_id).update(value: sObj[cf.salesforce_field])
        end
      else
        return "stream_custom_field_names=" + stream_custom_field_names.to_s # proprogate list of field names to caller
      end
    end
    nil # successful request
  end

  private

  def self.calculate_score_by_setting(metric, setting)
    m_t = setting.medium_threshold
    h_t = setting.high_threshold
    unless setting.is_positive
      metric *= -1
      m_t *= -1
      h_t *= -1
    end
    if metric < m_t
      0
    elsif metric < h_t
      50*setting.weight
    else
      100*setting.weight
    end
  end

  # Create all custom fields for a new Stream
  def create_custom_fields
    CustomFieldsMetadatum.where(organization:self.account.organization, entity_type: "Project").each { |cfm| CustomField.create(organization:self.account.organization, custom_fields_metadatum:cfm, customizable:self) }
  end
end
