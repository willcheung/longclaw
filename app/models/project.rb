# == Schema Information
#
# Table name: projects
#
#  id                  :uuid             not null, primary key
#  name                :string           default(""), not null
#  account_id          :uuid
#  is_public           :boolean          default(TRUE)
#  status              :string           default("Active")
#  description         :text
#  created_by          :uuid
#  updated_by          :uuid
#  owner_id            :uuid
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  is_confirmed        :boolean
#  category            :string           default("New Business")
#  deleted_at          :datetime
#  renewal_date        :date
#  contract_start_date :date
#  contract_end_date   :date
#  contract_arr        :decimal(14, 2)
#  renewal_count       :integer
#  has_case_study      :boolean          default(FALSE), not null
#  is_referenceable    :boolean          default(FALSE), not null
#  amount              :decimal(14, 2)
#  stage               :string
#  close_date          :date
#  expected_revenue    :decimal(14, 2)
#  probability         :decimal(5, 2)
#  forecast            :string
#  next_steps          :string
#  competition         :string
#
# Indexes
#
#  index_projects_on_account_id    (account_id)
#  index_projects_on_close_date    (close_date)
#  index_projects_on_deleted_at    (deleted_at)
#  index_projects_on_is_confirmed  (is_confirmed)
#  index_projects_on_is_public     (is_public)
#  index_projects_on_owner_id      (owner_id)
#  index_projects_on_status        (status)
#

include Utils
include ContextSmithParser

class Project < ActiveRecord::Base
  after_create  :create_custom_fields

  belongs_to  :account
  belongs_to  :project_owner, class_name: "User", foreign_key: "owner_id"
  has_many  :subscribers, class_name: "ProjectSubscriber", dependent: :destroy

  has_many  :notifications, -> { non_attachments }, dependent: :destroy
  has_many  :notifications_all, class_name: 'Notification', dependent: :destroy
  has_many  :attachments, -> { attachments }, class_name: 'Notification'
  has_many  :notifications_for_daily_email, -> {
    non_attachments.where("(is_complete IS FALSE AND created_at BETWEEN TIMESTAMP ? AND TIMESTAMP ?) OR (is_complete IS TRUE AND complete_date BETWEEN TIMESTAMP ? AND TIMESTAMP ?) OR (category = ? AND label = 'DaysInactive' AND is_complete IS FALSE)",
      Time.current.yesterday.midnight.utc, Time.current.yesterday.end_of_day.utc, Time.current.yesterday.midnight.utc, Time.current.yesterday.end_of_day.utc, Notification::CATEGORY[:Alert])
    .order(:is_complete, :original_due_date) }, class_name: "Notification"
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
    from_yesterday.reverse_chronological.where.not(category: Activity::CATEGORY[:Conversation])
    .where.not("(category = 'Alert' AND jsonb_array_length(email_messages) > 0 AND email_messages->0 ? 'days_inactive')") }, class_name: "Activity"
  #has_many  :other_activities_for_weekly_email, -> {
  #  from_lastweek.reverse_chronological
  #  .where.not(category: Activity::CATEGORY[:Conversation]) }, class_name: "Activity"

  belongs_to  :account_with_contacts_for_daily_email, -> { includes(:contacts).where(contacts: { created_at: Time.current.yesterday.midnight..Time.current.yesterday.end_of_day }) }, class_name: "Account", foreign_key: "account_id"
  # has_many  :contacts_for_daily_email, -> { where(created_at: (Time.current.yesterday.midnight..Time.current.yesterday.end_of_day)) }, through: "account", source: :contacts, class_name: 'Contact'

  ### project_members/contacts/users relations have 2 versions
  # v1: only shows confirmed, similar to old logic without project_members.status column
  # v2: "_all" version, ignores status
  has_many  :project_members, -> { confirmed.order('contact_id ASC') }, dependent: :destroy, class_name: 'ProjectMember'
  has_many  :project_members_all, class_name: "ProjectMember", dependent: :destroy
  has_many  :contacts, through: "project_members"
  has_many  :contacts_all, through: "project_members_all", source: :contact
  has_many  :users, through: "project_members"
  has_many  :users_all, through: "project_members_all", source: :user

  has_one  :salesforce_opportunity, foreign_key: "contextsmith_project_id", dependent: :nullify   # note: multiple SFDC opportunties may still map to a single project!
  has_many :custom_fields, as: :customizable, foreign_key: "customizable_uuid", dependent: :destroy

  # TODO: Combine visible_to and visible_to_admin scopes for a general "role" checker
  scope :visible_to, -> (organization_id, user_id) {
    select('DISTINCT(projects.*)')
        .joins([:account, 'LEFT OUTER JOIN project_members ON project_members.project_id = projects.id'])
        .where('accounts.organization_id = ? AND projects.is_confirmed = true AND projects.status = \'Active\' AND (projects.is_public = true OR projects.owner_id = ? OR (project_members.status = ? AND project_members.user_id = ?) OR ?)',
            organization_id, user_id, ProjectMember::STATUS[:Confirmed], user_id, User.find(user_id).admin?)
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
  scope :close_date_within, -> (range_description) { where(close_date: get_close_date_range(range_description)) }
  scope :is_active, -> { where status: 'Active' }
  scope :is_confirmed, -> { where is_confirmed: true }

  validates :name, presence: true, uniqueness: { scope: [:account, :project_owner, :is_confirmed], message: "There's already an opportunity with the same name." }

  STATUS = ["Active", "Completed", "On Hold", "Cancelled", "Archived"]
  CATEGORY = { Expansion: 'Expansion', Services: 'Services', NewBusiness: 'New Business', Pilot: 'Pilot', Support: 'Support', Other: 'Other' }
  MAPPABLE_FIELDS_META = { "name" => "Name", "category" => "Type", "description" => "Description", "renewal_date" => "Renewal Date", "amount" => "Deal Size", "stage" => "Stage", "close_date" => "Close Date", "expected_revenue" => "Expected Revenue", "probability" => "Probability", "forecast" => "Forecast", "next_steps" => "Next Steps" }  # format: backend field name => display name;  Unused: "contract_arr" => "Contract ARR", "contract_start_date" => "Contract Start Date", "contract_end_date" => "Contract End Date", "has_case_study" => "Has Case Study", "is_referenceable" => "Is Referenceable", "renewal_count" => "Renewal Count",
  RAGSTATUS = { Red: "Red", Amber: "Amber", Green: "Green" }
  CLOSE_DATE_RANGE = { ThisQuarterOpen: 'This Quarter - Open Opportunities', ThisQuarter: 'This Quarter', NextQuarter: 'Next Quarter', LastQuarter: 'Last Quarter', QTD: 'QTD', YTD: 'YTD', Closed: 'Before Today', Open: 'Today and After' }

  attr_accessor :num_activities_prev, :pct_from_prev

  # implementation of visible scope for individual projects
  def is_visible_to(user)
    account.organization == user.organization && is_confirmed && status == 'Active' && ( is_public || project_owner == user || users.include?(user) )
  end

  def is_linked_to_SFDC?
    self.salesforce_opportunity.present? || self.account.salesforce_accounts.present?
  end

  def self.count_tasks_per_project(array_of_project_ids)
    query = <<-SQL
        SELECT projects.id AS id,
               projects.name AS name,
               projects.amount AS amount,
               projects.close_date AS close_date,
               COUNT(*) FILTER (WHERE is_complete = FALSE ) AS open_risks
        FROM projects
        LEFT JOIN notifications
        ON projects.id = notifications.project_id
        AND notifications.category != '#{Notification::CATEGORY[:Attachment]}'
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

  def self.days_to_close_per_project(array_of_project_ids)
    query = <<-SQL
        SELECT projects.id AS id,
               projects.name AS name,
               projects.close_date AS close_date,
               projects.close_date - current_date AS days_to_close
        FROM projects
        WHERE projects.id IN ('#{array_of_project_ids.join("','")}')
        GROUP BY projects.id
        ORDER BY days_to_close DESC
      SQL
    result = Project.find_by_sql(query)
  end

  # for risk counts, show every risk regardless of private conversation
  def self.open_risk_count(array_of_project_ids)
    risks_per_project = Project.count_tasks_per_project(array_of_project_ids)
    Hash[risks_per_project.map { |p| [p.id, p.open_risks] }]
  end

  def self.new_risk_score(array_of_project_ids, time_zone)
    projects = Project.where(id: array_of_project_ids).group('projects.id')

    return [] if projects.empty?   # quit early if there are no projects

    # Initialize all scores with 0
    project_base = projects.sum(0)

    risk_settings = RiskSetting.where(level: projects.first.account.organization)

    # Risk / Engagement Ratio
    # sentiment_setting = risk_settings.find { |rs| rs.metric == RiskSetting::METRIC[:NegSentiment] }
    # pct_neg_sentiment_setting = risk_settings.find { |rs| rs.metric == RiskSetting::METRIC[:PctNegSentiment] }
    # project_engagement = projects.joins(:activities).where(activities: { category: Activity::CATEGORY[:Conversation] }).sum('jsonb_array_length(activities.email_messages)')
    # project_risks = projects.includes(:activities).where(activities: { category: Activity::CATEGORY[:Conversation] }).group('activities.id')
    # project_p_neg_sentiment = project_risks.each_with_object({}) do |p, result|
    #   risks = p.activities.select("(jsonb_array_elements(jsonb_array_elements(email_messages)->'sentimentItems')->>'score')::float AS sentiment_score")
    #     .map { |a| scale_sentiment_score(a.sentiment_score) }.select{ |score| score > sentiment_setting.high_threshold }.count
    #   result[p.id] = calculate_score_by_setting(risks.to_f/project_engagement[p.id], pct_neg_sentiment_setting)
    # end

    # Days Inactive
    days_inactive_setting = risk_settings.find { |rs| rs.metric == RiskSetting::METRIC[:DaysInactive] }
    project_inactivity_risk = projects.joins(:activities).where.not(activities: { category: [Activity::CATEGORY[:Note], Activity::CATEGORY[:Alert], Activity::CATEGORY[:NextSteps]] }).maximum('activities.last_sent_date') # get last_sent_date of last activity for each project
    project_inactivity_risk.each { |pid, last_sent_date| project_inactivity_risk[pid] = Time.current.in_time_zone(time_zone).to_date.mjd - last_sent_date.in_time_zone(time_zone).to_date.mjd } # convert last_sent_date to days inactive
    project_inactivity_risk.each { |pid, days_inactive| project_inactivity_risk[pid] = calculate_score_by_setting(days_inactive, days_inactive_setting) } # convert days inactive to effect on risk score

    # RAG Status
    rag_status_setting = risk_settings.find { |rs| rs.metric == RiskSetting::METRIC[:RAGStatus] }
    project_rag_status = Project.current_rag_score(array_of_project_ids)
    project_rag_status.each { |pid, rag_score| project_rag_status[pid] = calculate_score_by_setting(rag_score, rag_status_setting) }

    # Overall Score
    overall = [project_base, project_inactivity_risk, project_rag_status].each_with_object({}) { |current_hash, result_hash| result_hash.merge!(current_hash) { |pid, h1, h2| h1 + h2 } }
    overall.each { |pid, score| overall[pid] = score.round }
  end

  def new_risk_score(time_zone)
    risk_settings = RiskSetting.where(level: self.account.organization)
    # Risk / Engagement Ratio
    # sentiment_setting = risk_settings.find { |rs| rs.metric == RiskSetting::METRIC[:NegSentiment] }
    # pct_neg_sentiment_setting = risk_settings.find { |rs| rs.metric == RiskSetting::METRIC[:PctNegSentiment] }
    # engagement = self.conversations.sum('jsonb_array_length(activities.email_messages)')
    # if engagement.zero?
    #   percent_neg_sentiment = 0
    # else
    #   risks = self.conversations.select("(jsonb_array_elements(jsonb_array_elements(email_messages)->'sentimentItems')->>'score')::float AS sentiment_score")
    #     .map { |a| scale_sentiment_score(a.sentiment_score) }.select { |score| score > sentiment_setting.high_threshold }.count
    #   percent_neg_sentiment = Project.calculate_score_by_setting(risks.to_f/engagement, pct_neg_sentiment_setting)
    # end

    # Days Inactive
    days_inactive_setting = risk_settings.find { |rs| rs.metric == RiskSetting::METRIC[:DaysInactive] }
    last_sent_date = self.activities.where.not(category: [Activity::CATEGORY[:Note], Activity::CATEGORY[:Alert], Activity::CATEGORY[:NextSteps]]).maximum(:last_sent_date)
    days_inactive = last_sent_date.nil? ? 0 : Time.current.in_time_zone(time_zone).to_date.mjd - last_sent_date.in_time_zone(time_zone).to_date.mjd
    inactivity_risk = Project.calculate_score_by_setting(days_inactive, days_inactive_setting)

    # RAG Status
    rag_score_setting = risk_settings.find { |rs| rs.metric == RiskSetting::METRIC[:RAGStatus] }
    rag_status = self.activities.latest_rag_score.first
    rag_score = (rag_status ? Project.calculate_score_by_setting(rag_status.rag_score, rag_score_setting) : 0)

    # Overall Score
    (inactivity_risk + rag_score).round
  end

  # TODO: comment out this code once it's obsolete!
  def new_risk_score_trend(time_zone, day_range=14)
    risk_settings = RiskSetting.where(level: self.account.organization)
    
    # Risk / Engagement Ratio
    # sentiment_setting = risk_settings.find { |rs| rs.metric == RiskSetting::METRIC[:NegSentiment] }
    # pct_neg_sentiment_setting = risk_settings.find { |rs| rs.metric == RiskSetting::METRIC[:PctNegSentiment] }
    # total_engagement = self.conversations
    # if total_engagement.count.zero?
    #   pct_neg_sentiment_by_day = Array.new(day_range, 0)
    # else
    #   pct_neg_sentiment_by_day = ((day_range - 1).days.ago.in_time_zone(time_zone).to_date..Time.current.in_time_zone(time_zone).to_date).map do |date|
    #     engagement = total_engagement.where(last_sent_date: Time.at(0)..date).sum('jsonb_array_length(activities.email_messages)')
    #     if engagement.zero?
    #       0
    #     else
    #       risks = total_engagement.where(last_sent_date: Time.at(0)..date)
    #         .select("(jsonb_array_elements(jsonb_array_elements(email_messages)->'sentimentItems')->>'score')::float AS sentiment_score")
    #         .map { |a| scale_sentiment_score(a.sentiment_score) }.select { |score| score > sentiment_setting.high_threshold }.count
    #       Project.calculate_score_by_setting(risks.to_f/engagement, pct_neg_sentiment_setting)
    #     end
    #   end
    # end
    
    # Days Inactive
    days_inactive_setting = risk_settings.find { |rs| rs.metric == RiskSetting::METRIC[:DaysInactive] }
    activity_dates = self.activities.where.not(category: [Activity::CATEGORY[:Note], Activity::CATEGORY[:Alert], Activity::CATEGORY[:NextSteps]]).pluck(:last_sent_date).map { |d| d.in_time_zone(time_zone).to_date }.to_set
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

    [rag_score_by_day, days_inactive_by_day].transpose.map(&:sum)
  end

  def self.current_rag_score(array_of_project_ids)
    rag_per_project = Project.find_rag_status_per_project(array_of_project_ids)
    Hash[rag_per_project.map { |p| [p.project_id, p.rag_score ]}]
  end

  # query to generate Account Relationship Graph from DB entries
  def network_map(start_day=nil, end_day=nil, time_zone="UTC")
    if start_day
      if end_day
        conversation_date_pred = "AND (messages ->> 'sentDate')::integer BETWEEN #{start_day.to_i} AND #{end_day.to_i}"
        meeting_date_pred = "AND EXTRACT(EPOCH FROM last_sent_date AT TIME ZONE 'UTC' AT TIME ZONE '#{time_zone}') BETWEEN #{start_day.to_i} AND #{end_day.to_i}"
      else
        conversation_date_pred = "AND (messages ->> 'sentDate')::integer >= #{start_day.to_i}"
        meeting_date_pred = "AND EXTRACT(EPOCH FROM last_sent_date AT TIME ZONE 'UTC' AT TIME ZONE '#{time_zone}') >= #{start_day.to_i}"
      end
    elsif end_day
      conversation_date_pred = "AND (messages ->> 'sentDate')::integer <= #{end_day.to_i}"
      meeting_date_pred = "AND EXTRACT(EPOCH FROM last_sent_date AT TIME ZONE 'UTC' AT TIME ZONE '#{time_zone}') <= #{end_day.to_i}"
    end

    query = <<-SQL
      WITH email_and_meeting_activities AS
        (
          SELECT category,
                 messages ->> 'messageId'::text AS message_id,
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
          WHERE category = '#{Activity::CATEGORY[:Conversation]}'
          AND project_id = '#{self.id}'
          #{conversation_date_pred}
          GROUP BY 1,2,3,4,5
          UNION ALL
          SELECT category,
                 backend_id AS message_id,
                 jsonb_array_elements("from") ->> 'address' AS from,
                 jsonb_array_elements("to") ->> 'address' AS to,
                 CASE  
                    WHEN jsonb_array_length(cc) = 0 THEN NULL
                    ELSE jsonb_array_elements(cc) ->> 'address' 
                 END AS cc
          FROM activities
          WHERE category = '#{Activity::CATEGORY[:Meeting]}'
          AND project_id = '#{self.id}'
          #{meeting_date_pred}
          GROUP BY 1,2,3,4,5
        )
      SELECT "from" AS source,
             "to" AS target,
             COUNT(DISTINCT message_id) AS count
      FROM
        (SELECT "from", "to", message_id
          FROM email_and_meeting_activities
          WHERE "from" <> "to"
          UNION ALL
          SELECT "from", cc AS "to", message_id
          FROM email_and_meeting_activities
          WHERE "from" <> cc) t
      WHERE "to" IS NOT NULL
      GROUP BY 1,2;
    SQL
    result = Activity.find_by_sql(query).select{|r| valid_domain?(get_domain(r.source)) && valid_domain?(get_domain(r.target))}  # Note: this will also filter out any addresses in the result that contain domains too general to match to an account, e.g., @gmail.com, @hotmail.com, @yahoo.com
  end

  def arg_lookup
    # pinned = self.conversations.pinned
    meetings = self.meetings
    members = self.project_members_all
      .joins('LEFT JOIN users ON users.id = project_members.user_id LEFT JOIN contacts ON contacts.id = project_members.contact_id')
      .select('COALESCE(users.id, contacts.id) AS id, COALESCE(users.email, contacts.email) AS email, COALESCE(users.first_name, contacts.first_name) as first_name, COALESCE(users.last_name, contacts.last_name) AS last_name, COALESCE(users.title, contacts.title) AS title, users.image_url AS profile_img_url, project_members.status, project_members.buyer_role, users.department AS team, users.id IS NULL AS is_external').where("users.email IS NOT NULL OR contacts.email IS NOT NULL")
      .where(status: [ProjectMember::STATUS[:Confirmed], ProjectMember::STATUS[:Pending]])

    # TODO: For Demo Only
    if ENV['demo_opp_ids'].present? && ENV['demo_opp_ids'].split(',').include?(self.id) && ENV['demo_contact_emails'].present?
      demo_opps_percontact_h = {}
      demo_accts_percontact_h = {}

      demo_opps_h = {}
      demo_opps_h["348fe645-47e4-4151-996b-5cfd2adf31c8"] = {id: "348fe645-47e4-4151-996b-5cfd2adf31c8", name: "Wayne Global Enterprises", dealSize: 500000, stage: "Proposal", closeDate: Date.tomorrow + 100.days}

      demo_opps_h["856a7a3b-75da-4ebb-a515-0b7dea1d03c0"] = {id: "856a7a3b-75da-4ebb-a515-0b7dea1d03c0", name: "Frost Intl.", dealSize: 225000, stage: "Qualification", closeDate: Date.tomorrow + 1.months}
      demo_opps_h["ec713f6c-2931-4be9-9fd5-8b1122bf6dec"] = {id: "ec713f6c-2931-4be9-9fd5-8b1122bf6dec", name: "Xavier SGY", dealSize: 50000, stage: "Prospecting", closeDate: Date.tomorrow + 2.months}

      demo_accts_h = {}
      demo_accts_h["f0b73a71-29d5-4d9c-846d-32e895dec5c8"] = {id: "f0b73a71-29d5-4d9c-846d-32e895dec5c8", name: "Wakanda", category: "Customer"}

      ENV['demo_contact_emails'].split(',').each do |email|
        c = self.account.contacts.find_by(email: email.strip) #|| Contact.find_by(email: email.strip)
        demo_opps_percontact_h[c.id] = demo_opps_h
        demo_accts_percontact_h[c.id] = demo_accts_h
      end
    end

    members.map do |m|
      profile = Profile.find_or_create_by_email(m.email)
      #pin = pinned.select { |p| p.from.first.address == m.email || p.posted_by == m.id }
      meet = meetings.select { |p| p.from.first.address == m.email || p.posted_by == m.id }
      is_suggested = m.status == ProjectMember::STATUS[:Pending]
      {
        name: get_full_name(m),
        domain: get_domain(m.email),
        email: m.email,
        title: (m.title if m.title.present?) || (profile.title if profile.present?),
        profile_img_url: m.profile_img_url || (profile.profileimg_url if profile.present?),
        buyer_role: m.buyer_role,
        team: m.team,
        #key_activities: pin.length,
        meetings: meet.length,
        is_external: m.is_external,
        is_suggested: is_suggested,
        opportunities: demo_opps_percontact_h && (demo_opps_percontact_h.keys.include? m.id) ? demo_opps_percontact_h[m.id] : {},
        accounts: demo_accts_percontact_h && (demo_accts_percontact_h.keys.include? m.id) ? demo_accts_percontact_h[m.id] : {}
      }
    end.compact

    # all_members = @project.project_members_all
    # suggested_members = all_members.pending.map { |pm| pm.user_id || pm.contact_id }
    # rejected_members = all_members.rejected.map { |pm| pm.user_id || pm.contact_id }
    # buyer_roles = all_members.group(:id)
    # (@project.users_all + @project.contacts_all).map do |m|
    #   next if rejected_members.include?(m.id)
    #   pin = pinned.select { |p| p.from.first.address == m.email || p.posted_by == m.id }
    #   meet = meetings.select { |p| p.from.first.address == m.email || p.posted_by == m.id }
    #   suggested = suggested_members.include?(m.id) ? ' *' : ''
    #   {
    #     name: get_full_name(m) + suggested,
    #     domain: get_domain(m.email),
    #     email: m.email,
    #     title: m.title,
    #     key_activities: pin.length,
    #     meetings: meet.length
    #   }
    # end.compact
  end

  def contact_relationship_metrics
  #   name
  #   title
  #   buyer_role
  #   last sent by
  #   last sent
  #   last reply
  #   last meeting
  #   next meeting
    query = <<-SQL
      WITH future_meetings AS (
        SELECT last_sent_date, "from", "to"
        FROM activities
        WHERE project_id = '#{self.id}' AND category = '#{Activity::CATEGORY[:Meeting]}' AND last_sent_date > TIMESTAMP '#{Time.current.utc}'
      ), past_meetings AS (
        SELECT last_sent_date, "from", "to"
        FROM activities
        WHERE project_id = '#{self.id}' AND category = '#{Activity::CATEGORY[:Meeting]}' AND last_sent_date <= TIMESTAMP '#{Time.current.utc}'
      ), user_emails AS (
        SELECT activities.id,
               messages ->> 'messageId' AS message_id,
               to_timestamp((messages ->> 'sentDate')::integer) AS sent_date,
               jsonb_array_elements(messages -> 'from') ->> 'address' AS from_address,
               jsonb_array_elements(messages -> 'from') ->> 'personal' AS from_personal,
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
        WHERE project_id = '#{self.id}' AND category = '#{Activity::CATEGORY[:Conversation]}'
      )
      SELECT contacts.id,
             contacts.email,
             contacts.first_name,
             contacts.last_name,
             contacts.title,
             contacts.background_info,
             project_members.id AS project_member_id,
             project_members.status,
             project_members.buyer_role,
             received_emails.from_address AS last_sent_by_address,
             received_emails.from_personal AS last_sent_by_personal,
             received_emails.max_sent_date AS last_sent_date,
             received_emails.id AS last_sent_id,
             received_emails.message_id AS last_sent_message_id,
             sent_emails.max_reply_date AS last_reply_date,
             sent_emails.id AS last_reply_id,
             sent_emails.message_id AS last_reply_message_id,
             MAX(past_meetings.last_sent_date) AS last_meeting_date,
             MIN(future_meetings.last_sent_date) AS next_meeting_date
      FROM contacts
      JOIN project_members
      ON contacts.id = project_members.contact_id AND project_members.status != #{ProjectMember::STATUS[:Rejected]}
      JOIN projects
      ON projects.id = project_members.project_id
      LEFT JOIN future_meetings
      ON (future_meetings.from || future_meetings.to) @> ('[{"address":"' || contacts.email || '"}]')::jsonb
      LEFT JOIN past_meetings
      ON (past_meetings.from || past_meetings.to) @> ('[{"address":"' || contacts.email || '"}]')::jsonb
      LEFT JOIN (
        SELECT id, message_id, sent.*
        FROM user_emails
        JOIN (
          SELECT from_address, MAX(sent_date) AS max_reply_date
          FROM user_emails
          GROUP BY 1
        ) AS sent
        ON user_emails.sent_date = sent.max_reply_date AND sent.from_address = user_emails.from_address
      ) AS sent_emails
      ON contacts.email = sent_emails.from_address
      LEFT JOIN (
        SELECT id, message_id, from_address, from_personal, received.*
        FROM user_emails
        JOIN (
          SELECT recipient, MAX(sent_date) AS max_sent_date
          FROM (
            SELECT "to" AS recipient, sent_date
            FROM user_emails
            UNION ALL
            SELECT cc AS recipient, sent_date
            FROM user_emails
           ) t
          GROUP BY 1
        ) AS received
        ON user_emails.sent_date = received.max_sent_date AND received.recipient IN (user_emails.to, user_emails.cc)
      ) AS received_emails
      ON contacts.email = received_emails.recipient
      WHERE projects.id = '#{self.id}'
      GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17
      ORDER BY last_sent_date DESC
    SQL

    Contact.find_by_sql(query)
  end

  # generate options for Person Filter on Timeline, from activities visible to user with user_email
  def all_involved_people(user_email)
    activities = self.activities.visible_to(user_email).select(:from, :to, :cc, :posted_by).includes(:user)

    people = []
    tempSet = Set.new
    activities.each do |a|
      a.email_addresses.each do |e|
        tempSet.add(e) unless e.blank? || get_domain(e) == 'resources.calendar.google.com' # exclude Google Calendar resource emails
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
  # NOTE: to_timestamp converts epoch to timestamp with UTC timezone, but Activity.last_sent_date usually saved as timestamp without timezone
  # Therefore we need to convert Activity.last_sent_date to timestamp with UTC timezone, then convert to timestamp with user timezone
  def daily_activities(time_zone)
    query = <<-SQL
      -- E-mail conversations
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
      SELECT date(last_sent_date AT TIME ZONE 'UTC' AT TIME ZONE '#{time_zone}') as last_sent_date,
            '#{Activity::CATEGORY[:Meeting]}' as category,
            count(*) as activity_count
      FROM activities
      WHERE category = '#{Activity::CATEGORY[:Meeting]}' and project_id = '#{self.id}'
      GROUP BY date(last_sent_date AT TIME ZONE 'UTC' AT TIME ZONE '#{time_zone}'), category
      ORDER BY date(last_sent_date AT TIME ZONE 'UTC' AT TIME ZONE '#{time_zone}')
      )
      UNION ALL
      (
      -- Notes
      SELECT date(last_sent_date AT TIME ZONE 'UTC' AT TIME ZONE '#{time_zone}') as last_sent_date,
            '#{Activity::CATEGORY[:Note]}' as category,
            count(*) as activity_count
      FROM activities
      WHERE category = '#{Activity::CATEGORY[:Note]}' and project_id = '#{self.id}'
      GROUP BY date(last_sent_date AT TIME ZONE 'UTC' AT TIME ZONE '#{time_zone}'), category
      ORDER BY date(last_sent_date AT TIME ZONE 'UTC' AT TIME ZONE '#{time_zone}')
      )
      UNION ALL
      (
      -- JIRA
      SELECT date(last_sent_date AT TIME ZONE 'UTC' AT TIME ZONE '#{time_zone}') as last_sent_date,
            '#{Activity::CATEGORY[:JIRA]}' as category,
            count(*) as activity_count
      FROM activities
      WHERE category = '#{Activity::CATEGORY[:JIRA]}' and project_id = '#{self.id}'
      GROUP BY date(last_sent_date AT TIME ZONE 'UTC' AT TIME ZONE '#{time_zone}'), category
      ORDER BY date(last_sent_date AT TIME ZONE 'UTC' AT TIME ZONE '#{time_zone}')
      )
      UNION ALL
      (
      -- Salesforce
      SELECT date(last_sent_date AT TIME ZONE 'UTC' AT TIME ZONE '#{time_zone}') as last_sent_date,
            '#{Activity::CATEGORY[:Salesforce]}' as category,
            count(*) as activity_count
      FROM activities
      WHERE category = '#{Activity::CATEGORY[:Salesforce]}' and project_id = '#{self.id}'
      GROUP BY date(last_sent_date AT TIME ZONE 'UTC' AT TIME ZONE '#{time_zone}'), category
      ORDER BY date(last_sent_date AT TIME ZONE 'UTC' AT TIME ZONE '#{time_zone}')
      )
      UNION ALL
      (
      -- Zendesk
      SELECT date(last_sent_date AT TIME ZONE 'UTC' AT TIME ZONE '#{time_zone}') as last_sent_date,
            '#{Activity::CATEGORY[:Zendesk]}' as category,
            count(*) as activity_count
      FROM activities
      WHERE category = '#{Activity::CATEGORY[:Zendesk]}' and project_id = '#{self.id}'
      GROUP BY date(last_sent_date AT TIME ZONE 'UTC' AT TIME ZONE '#{time_zone}'), category
      ORDER BY date(last_sent_date AT TIME ZONE 'UTC' AT TIME ZONE '#{time_zone}')
      )
      UNION ALL
      (
      -- Alert
      SELECT date(last_sent_date AT TIME ZONE 'UTC' AT TIME ZONE '#{time_zone}') as last_sent_date,
            '#{Activity::CATEGORY[:Alert]}' as category,
            count(*) as activity_count
      FROM activities
      WHERE category = '#{Activity::CATEGORY[:Alert]}' and project_id = '#{self.id}'
      GROUP BY date(last_sent_date AT TIME ZONE 'UTC' AT TIME ZONE '#{time_zone}'), category
      ORDER BY date(last_sent_date AT TIME ZONE 'UTC' AT TIME ZONE '#{time_zone}')
      )
      UNION ALL
      (
      -- Basecamp2
      SELECT date(last_sent_date AT TIME ZONE 'UTC' AT TIME ZONE '#{time_zone}') as last_sent_date,
            '#{Activity::CATEGORY[:Basecamp2]}' as category,
            count(*) as activity_count
      FROM activities
      WHERE category = '#{Activity::CATEGORY[:Basecamp2]}' and project_id = '#{self.id}'
      GROUP BY date(last_sent_date AT TIME ZONE 'UTC' AT TIME ZONE '#{time_zone}'), category
      ORDER BY date(last_sent_date AT TIME ZONE 'UTC' AT TIME ZONE '#{time_zone}')
      )
      UNION ALL
      (
      -- NextSteps
      SELECT date(last_sent_date AT TIME ZONE 'UTC' AT TIME ZONE '#{time_zone}') as last_sent_date,
            '#{Activity::CATEGORY[:NextSteps]}' as category,
            count(*) as activity_count
      FROM activities
      WHERE category = '#{Activity::CATEGORY[:NextSteps]}' and project_id = '#{self.id}'
      GROUP BY date(last_sent_date AT TIME ZONE 'UTC' AT TIME ZONE '#{time_zone}'), category
      ORDER BY date(last_sent_date AT TIME ZONE 'UTC' AT TIME ZONE '#{time_zone}')
      )
      UNION ALL
      (
      -- Attachment
      SELECT date(sent_date AT TIME ZONE 'UTC' AT TIME ZONE '#{time_zone}') as last_sent_date,
            '#{Notification::CATEGORY[:Attachment]}' as category,
            count(*) as activity_count
      FROM notifications
      WHERE category = '#{Notification::CATEGORY[:Attachment]}' and project_id = '#{self.id}'
      GROUP BY date(sent_date AT TIME ZONE 'UTC' AT TIME ZONE '#{time_zone}'), category
      ORDER BY date(sent_date AT TIME ZONE 'UTC' AT TIME ZONE '#{time_zone}')
      )
    SQL

    Activity.find_by_sql(query)
  end

  # This is the SQL query that gets the daily activities over a date range, by default the last 14 days through current day.
  # Used for time bounded time series
  def daily_activities_in_date_range(time_zone, start_day=14.days.ago.midnight.utc, end_day=Time.current.end_of_day.utc)
    domain = account.organization.domain
    query = <<-SQL
      -- This controls the dates returned by the query
      WITH time_series as (
        SELECT '#{self.id}'::uuid as project_id, generate_series(date(TIMESTAMP '#{start_day}'), date(TIMESTAMP '#{end_day}'), INTERVAL '1 day') AS days LIMIT #{(end_day - start_day).ceil / 86400}
      ), conversations_last_14d AS (
        SELECT DISTINCT
            project_id,
            to_timestamp((messages ->> 'sentDate')::integer) AS sent_date,
            messages ->> 'messageId'::text AS message_id
        FROM activities,
        LATERAL jsonb_array_elements(email_messages) messages
        WHERE category = '#{Activity::CATEGORY[:Conversation]}'
          AND project_id = '#{self.id}'
          AND (messages ->> 'sentDate')::integer BETWEEN #{start_day.to_i} AND #{end_day.to_i}
      )
      (
      -- E-mail Conversations accessed using Common Table Expression set above using WITH 
      SELECT time_series.project_id as project_id, date(time_series.days) as last_sent_date, '#{Activity::CATEGORY[:Conversation]}' as category, count(activities.*) as num_activities
      FROM time_series
      LEFT JOIN (SELECT DISTINCT sent_date, project_id, message_id
                 FROM conversations_last_14d
                 ) as activities
        ON activities.project_id = time_series.project_id and date_trunc('day', sent_date AT TIME ZONE '#{time_zone}') = time_series.days
      GROUP BY time_series.project_id, days, category
      ORDER BY time_series.project_id, days ASC
      )
      UNION ALL
      (
      -- Meetings directly from activities table
      SELECT time_series.project_id as project_id, date(time_series.days) as last_sent_date, '#{Activity::CATEGORY[:Meeting]}' as category, count(meetings.*) as num_activities
      FROM time_series
      LEFT JOIN (SELECT last_sent_date as sent_date, project_id
                   FROM activities 
                  WHERE category = '#{Activity::CATEGORY[:Meeting]}' and project_id = '#{self.id}'AND EXTRACT(EPOCH FROM last_sent_date) BETWEEN #{start_day.to_i} AND #{end_day.to_i}
                ) as meetings
        ON meetings.project_id = time_series.project_id and date_trunc('day', meetings.sent_date AT TIME ZONE 'UTC' AT TIME ZONE '#{time_zone}') = time_series.days
      GROUP BY time_series.project_id, days, category
      ORDER BY time_series.project_id, days ASC
      )
      UNION ALL
      (
      -- JIRA directly from activities table
      SELECT time_series.project_id as project_id, date(time_series.days) as last_sent_date, '#{Activity::CATEGORY[:JIRA]}' as category, count(jiras.*) as num_activities
      FROM time_series
      LEFT JOIN (SELECT last_sent_date as sent_date, project_id
                  FROM activities where category = '#{Activity::CATEGORY[:JIRA]}' and project_id = '#{self.id}' and EXTRACT(EPOCH FROM last_sent_date) BETWEEN #{start_day.to_i} AND #{end_day.to_i}
                ) as jiras
        ON jiras.project_id = time_series.project_id and date_trunc('day', jiras.sent_date AT TIME ZONE 'UTC' AT TIME ZONE '#{time_zone}') = time_series.days
      GROUP BY time_series.project_id, days, category
      ORDER BY time_series.project_id, days ASC
      )
      UNION ALL
      (
      -- Salesforce directly from activities table
      SELECT time_series.project_id as project_id, date(time_series.days) as last_sent_date, '#{Activity::CATEGORY[:Salesforce]}' as category, count(salesforces.*) as num_activities
      FROM time_series
      LEFT JOIN (SELECT last_sent_date as sent_date, project_id
                  FROM activities where category = '#{Activity::CATEGORY[:Salesforce]}' and project_id = '#{self.id}' and EXTRACT(EPOCH FROM last_sent_date) BETWEEN #{start_day.to_i} AND #{end_day.to_i}
                ) as salesforces
        ON salesforces.project_id = time_series.project_id and date_trunc('day', salesforces.sent_date AT TIME ZONE 'UTC' AT TIME ZONE '#{time_zone}') = time_series.days
      GROUP BY time_series.project_id, days, category
      ORDER BY time_series.project_id, days ASC
      )
      UNION ALL
      (
      -- Zendesk directly from activities table
      SELECT time_series.project_id as project_id, date(time_series.days) as last_sent_date, '#{Activity::CATEGORY[:Zendesk]}' as category, count(zendesks.*) as num_activities
      FROM time_series
      LEFT JOIN (SELECT last_sent_date as sent_date, project_id
                  FROM activities where category = '#{Activity::CATEGORY[:Zendesk]}' and project_id = '#{self.id}' and EXTRACT(EPOCH FROM last_sent_date) BETWEEN #{start_day.to_i} AND #{end_day.to_i}
                ) as zendesks
        ON zendesks.project_id = time_series.project_id and date_trunc('day', zendesks.sent_date AT TIME ZONE 'UTC' AT TIME ZONE '#{time_zone}') = time_series.days
      GROUP BY time_series.project_id, days, category
      ORDER BY time_series.project_id, days ASC
      )
      UNION ALL
      (
      -- Basecamp2 directly from activities table
      SELECT time_series.project_id as project_id, date(time_series.days) as last_sent_date, '#{Activity::CATEGORY[:Basecamp2]}' as category, count(basecamp2s.*) as num_activities
      FROM time_series
      LEFT JOIN (SELECT last_sent_date as sent_date, project_id
                  FROM activities where category = '#{Activity::CATEGORY[:Basecamp2]}' and project_id = '#{self.id}' and EXTRACT(EPOCH FROM last_sent_date) BETWEEN #{start_day.to_i} AND #{end_day.to_i}
                ) as basecamp2s
        ON basecamp2s.project_id = time_series.project_id and date_trunc('day', basecamp2s.sent_date AT TIME ZONE 'UTC' AT TIME ZONE '#{time_zone}') = time_series.days
      GROUP BY time_series.project_id, days, category
      ORDER BY time_series.project_id, days ASC
      )
      UNION ALL
      (
      -- Sent Attachments directly from notifications table
      SELECT time_series.project_id as project_id, date(time_series.days) as last_sent_date, '#{Notification::CATEGORY[:Attachment]}' as category, count(attachments.*) as num_activities
      FROM time_series
      LEFT JOIN (SELECT sent_date, project_id
                  FROM notifications where category = '#{Notification::CATEGORY[:Attachment]}' and project_id = '#{self.id}' and EXTRACT(EPOCH FROM sent_date) BETWEEN #{start_day.to_i} AND #{end_day.to_i}
                  AND description::jsonb->'from'->0->>'address' LIKE '%#{domain}'
                ) as attachments
        ON attachments.project_id = time_series.project_id and date_trunc('day', attachments.sent_date AT TIME ZONE 'UTC' AT TIME ZONE '#{time_zone}') = time_series.days
      GROUP BY time_series.project_id, days, category
      ORDER BY time_series.project_id, days ASC
      )
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

  def activities_moving_average(time_zone, segment_size=30, start_day=14.days.ago.midnight.utc, end_day=Time.current.end_of_day.utc)
    domain = account.organization.domain
    num_days = (end_day - start_day).round/86400 # calculate number of days in this date range, find number of seconds and divide by seconds/day
    query = <<-SQL
      WITH time_series as (
        SELECT generate_series(date (TIMESTAMP '#{start_day}' AT TIME ZONE '#{time_zone}' - INTERVAL '#{segment_size} days'), date(TIMESTAMP '#{end_day}' AT TIME ZONE '#{time_zone}'), INTERVAL '1 day') as days LIMIT #{num_days + segment_size}
      ), activities_by_day AS (
        SELECT date(time_series.days) as date, COUNT(DISTINCT emails.*) + COUNT(DISTINCT other_activities.*) AS num_activities
        FROM time_series
        LEFT JOIN (SELECT messages ->> 'messageId'::text AS message_id,
                          to_timestamp((messages ->> 'sentDate')::integer) AS sent_date
                    FROM activities,
                    LATERAL jsonb_array_elements(email_messages) messages
                    WHERE category = 'Conversation'
                    AND activities.project_id = '#{self.id}'
                    AND to_timestamp((messages ->> 'sentDate')::integer) BETWEEN (TIMESTAMP'#{start_day}' - INTERVAL '#{segment_size} days') AND (TIMESTAMP'#{end_day}')
                    GROUP BY 1,2
                   ) as emails
          ON date (emails.sent_date AT TIME ZONE '#{time_zone}') = time_series.days
        LEFT JOIN (SELECT last_sent_date as sent_date
                    FROM activities where category in ('#{(Activity::CATEGORY.values - [Activity::CATEGORY[:Conversation], Activity::CATEGORY[:Note], Activity::CATEGORY[:Alert]]).join("','")}') and project_id = '#{self.id}' 
                    AND EXTRACT(EPOCH FROM last_sent_date AT TIME ZONE '#{time_zone}') BETWEEN '#{(start_day - segment_size.days).to_i}' AND '#{end_day.to_i}'
                  ) as other_activities
          ON date (other_activities.sent_date AT TIME ZONE 'UTC' AT TIME ZONE '#{time_zone}') = time_series.days
        LEFT JOIN (SELECT sent_date
                  FROM notifications where category = '#{Notification::CATEGORY[:Attachment]}' and project_id = '#{self.id}' 
                  AND EXTRACT(EPOCH FROM sent_date AT TIME ZONE '#{time_zone}') BETWEEN '#{(start_day - segment_size.days).to_i}' AND '#{end_day.to_i}'
                  AND description::jsonb->'from'->0->>'address' LIKE '%#{domain}'
                ) as attachments
          ON date (attachments.sent_date AT TIME ZONE 'UTC' AT TIME ZONE '#{time_zone}') = time_series.days
        GROUP BY time_series.days
        ORDER BY time_series.days ASC
      )
      SELECT date(time_series.days) AS date, num_activities, SUM(num_activities) OVER (ORDER BY activities_by_day.date ROWS BETWEEN #{segment_size - 1} PRECEDING AND CURRENT ROW) AS moving_sum, AVG(num_activities) OVER (ORDER BY activities_by_day.date ROWS BETWEEN #{segment_size - 1} PRECEDING AND CURRENT ROW) AS moving_avg
      FROM time_series
      LEFT JOIN activities_by_day
      ON activities_by_day.date = time_series.days
    SQL
    result = Project.find_by_sql(query)
    result.last(num_days).map(&:moving_avg).map(&:to_f) # take the last num_days results
  end

  def self.count_activities_by_day_sparkline(array_of_project_ids, time_zone, days_ago=7)
    query = <<-SQL
      WITH time_series as (
        SELECT *
          from (SELECT generate_series(date (CURRENT_TIMESTAMP AT TIME ZONE '#{time_zone}' - INTERVAL '#{days_ago} days'), CURRENT_TIMESTAMP AT TIME ZONE '#{time_zone}', INTERVAL '1 day') as days) t1
                CROSS JOIN
               (SELECT id as project_id from projects where id in ('#{array_of_project_ids.join("','")}')) t2
       )
      SELECT time_series.project_id as id, date(time_series.days) as date, count(DISTINCT emails.*) + count(DISTINCT other_activities.*) as num_activities
      FROM time_series
      LEFT JOIN (SELECT sent_date, project_id
                 FROM email_activities_last_14d where project_id in ('#{array_of_project_ids.join("','")}') and sent_date::integer > EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP AT TIME ZONE '#{time_zone}' - INTERVAL '#{days_ago} days'))
                 ) as emails
        ON emails.project_id = time_series.project_id and date_trunc('day', to_timestamp(emails.sent_date::integer) AT TIME ZONE '#{time_zone}') = time_series.days
      LEFT JOIN (SELECT last_sent_date as sent_date, project_id
                  FROM activities where category in ('#{(Activity::CATEGORY.values - [Activity::CATEGORY[:Conversation], Activity::CATEGORY[:Note], Activity::CATEGORY[:Alert], Activity::CATEGORY[:NextSteps]]).join("','")}') and project_id in ('#{array_of_project_ids.join("','")}') and EXTRACT(EPOCH FROM last_sent_date AT TIME ZONE '#{time_zone}') > EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP AT TIME ZONE '#{time_zone}' - INTERVAL '#{days_ago} days'))
                ) as other_activities
        ON other_activities.project_id = time_series.project_id and date_trunc('day', other_activities.sent_date AT TIME ZONE 'UTC' AT TIME ZONE '#{time_zone}') = time_series.days
      GROUP BY time_series.project_id, days
      ORDER BY time_series.project_id, days ASC
    SQL

    result = Project.find_by_sql(query)
    result = result.group_by(&:id)
    result.each { |pid, project| result[pid] = project.map(&:num_activities) }
  end

  # Top Active Streams/Engagement Last 7d
  def self.find_include_sum_activities(array_of_project_ids, epoch_time_start=false, epoch_time_end=0)
    epoch_time_end = epoch_time_end.hours.ago.to_i
    epoch_time_start = epoch_time_start ? epoch_time_start.hours.ago.to_i : 0

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
      WHERE (t.category = '#{Activity::CATEGORY[:Conversation]}' AND (sent_date::integer BETWEEN #{epoch_time_start} AND #{epoch_time_end}))
      OR (t.category in ('#{(Activity::CATEGORY.values - [Activity::CATEGORY[:Conversation], Activity::CATEGORY[:Note], Activity::CATEGORY[:Alert]]).join("','")}') AND (EXTRACT(EPOCH FROM last_sent_date) BETWEEN #{epoch_time_start} AND #{epoch_time_end}))
      GROUP BY projects.id
      ORDER BY num_activities DESC
    SQL
    return Project.find_by_sql(query)
  end

  # Top Active Opportunities/Engagement of e-mails, meetings, and all activity within a period
  # Parameters:   array_of_project_ids - ids of opportunities
  #               domain - domain of the organization (not used)
  #               array_of_user_emails (required) - e-mails of users to be used to determine if an e-mail is outbound/sent or inbound/received (e.g., if from perspective of a single user, this contains only this user's e-mail address; if want to use all users for the current user's organization, specify them).)  
  #               start_day - the starting time (timestamp) of the reporting period; Default is midnight 14 days ago in current user's timezone
  #               end_day - the starting time (timestamp) of the reporting period; Default is midnight current day in current user's timezone
  # Note: this query will not report anything without a non-empty array in array_of_user_emails!
  def self.count_activities_by_category(array_of_project_ids, domain, array_of_user_emails, start_day=14.days.ago.midnight.utc, end_day=Time.current.end_of_day.utc)
    return [] if array_of_user_emails.blank?
    query = <<-SQL
      WITH projects_from_array AS (
        SELECT id, name FROM projects WHERE projects.id IN ('#{array_of_project_ids.join("','")}')
      ), emails AS (
        SELECT project_id,
            messages ->> 'messageId'::text AS message_id,
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
        WHERE category = 'Conversation'
          AND project_id IN ('#{array_of_project_ids.join("','")}')
          AND (messages ->> 'sentDate')::integer BETWEEN #{start_day.to_i} AND #{end_day.to_i}
      ), emails_sent AS (
        SELECT DISTINCT project_id, message_id
          FROM users
          INNER JOIN emails
          ON (users.email IN (emails.from))
          WHERE users.email IN (#{array_of_user_emails.map{|u| User.sanitize(u)}.join(',')})
      ), emails_received AS (
        SELECT DISTINCT project_id, message_id
          FROM users
          INNER JOIN emails
          ON (users.email IN (emails.to, emails.cc))
          WHERE users.email IN (#{array_of_user_emails.map{|u| User.sanitize(u)}.join(',')})
        EXCEPT
        SELECT * FROM emails_sent
      ), meetings AS (
        SELECT DISTINCT activities.id, project_id, email_messages AS end_epoch, last_sent_date_epoch AS start_epoch -- "to" AS attendees
          FROM activities
          JOIN projects_from_array ON activities.project_id = projects_from_array.id,
          LATERAL jsonb_array_elements(email_messages) messages
          WHERE activities.category = '#{Activity::CATEGORY[:Meeting]}'
          AND EXTRACT(EPOCH FROM last_sent_date) BETWEEN #{start_day.to_i} AND #{end_day.to_i}
          AND project_id IN ('#{array_of_project_ids.join("','")}')
          AND (#{ array_of_user_emails.map{|e| "\"from\" || \"to\" || cc @> ('[{\"address\":\"" + User.sanitize(e)[1..-2] + "\"}]')::jsonb"}.join(" OR ") })
          --AND ((messages ->> 'end_epoch')::integer BETWEEN #{start_day.to_i} AND #{end_day.to_i}
      )
      SELECT *
      FROM (
        -- E-mails
        SELECT projects.id, projects.name, activity_count_by_category.category, activity_count_by_category.num_activities
        FROM projects_from_array AS projects
        JOIN
        (
         SELECT project_id, 'E-mails Sent' AS category, COUNT(DISTINCT message_id) AS num_activities
          FROM emails_sent
          GROUP BY project_id, category
          HAVING COUNT(DISTINCT message_id) > 0
          UNION ALL
         SELECT project_id, 'E-mails Received' AS category, COUNT(DISTINCT message_id) AS num_activities
          FROM emails_received
          GROUP BY project_id, category
          HAVING COUNT(DISTINCT message_id) > 0
        ) AS activity_count_by_category
        ON projects.id = activity_count_by_category.project_id
        UNION ALL
        -- Meetings
        SELECT t.project_id, t.name, '#{Activity::CATEGORY[:Meeting]}', COUNT(DISTINCT t.id) AS num_activities
        FROM (
          SELECT DISTINCT m.id, project_id, proj.name, start_epoch AS start_t, jsonb_array_elements(end_epoch) ->> 'end_epoch' AS end_t
          FROM meetings AS m
          JOIN projects_from_array AS proj ON m.project_id = proj.id
          ) AS t
        GROUP BY t.project_id, t.name
        UNION ALL
        -- Other activity
        SELECT projects.id, projects.name, a.category, COUNT(distinct a.id) AS num_activities
        FROM projects_from_array AS projects 
        LEFT JOIN (
          SELECT id,
                 category,
                 project_id,
                 last_sent_date
          FROM activities
          WHERE project_id IN ('#{array_of_project_ids.join("','")}')
            AND category in ('#{(Activity::CATEGORY.values - [Activity::CATEGORY[:Conversation], Activity::CATEGORY[:Meeting], Activity::CATEGORY[:Note], Activity::CATEGORY[:Alert], Activity::CATEGORY[:NextSteps]]).join("','")}')
            AND EXTRACT(EPOCH FROM last_sent_date) BETWEEN #{start_day.to_i} AND #{end_day.to_i}
          ) AS a
        ON projects.id = a.project_id
        GROUP BY projects.id, projects.name, a.category
        UNION ALL
        -- Attachments
        SELECT projects.id, projects.name, '#{Notification::CATEGORY[:Attachment]}' AS category, COUNT(*) AS num_activities
        FROM notifications
        JOIN projects ON projects.id = notifications.project_id
        WHERE project_id IN ('#{array_of_project_ids.join("','")}')
        AND notifications.category = '#{Notification::CATEGORY[:Attachment]}'
        AND (EXTRACT(EPOCH FROM sent_date) BETWEEN #{start_day.to_i} AND #{end_day.to_i})
        AND notifications.description::jsonb->'from'->0->>'address' IN (#{array_of_user_emails.map{|u| User.sanitize(u)}.join(',')})
        GROUP BY projects.id, projects.name, notifications.category
      ) as q
      ORDER BY q.num_activities DESC, UPPER(q.name)
    SQL
    Project.find_by_sql(query)
  end

  # units for time result = seconds
  def interaction_time_by_user(array_of_users)
    email_word_counts = User.team_usage_report([id], array_of_users.pluck(:email))
    meeting_time_seconds = User.meeting_report([id], array_of_users.pluck(:email))
    attachment_counts = User.sent_attachments_count([id], array_of_users.pluck(:email))

    result = email_word_counts.map do |u|
      user = array_of_users.find { |usr| usr.email == u.email }
      # convert word count of inbound and outbound emails to approx. time in seconds
      inbound = (u.inbound.to_i / User::WORDS_PER_SEC[:Read]).round
      outbound = (u.outbound.to_i / User::WORDS_PER_SEC[:Write]).round
      Hashie::Mash.new(id: user.id, email: user.email, name: get_full_name(user), 'Read E-mails': inbound, 'Sent E-mails': outbound, 'Meetings': 0, 'Attachments': 0 , total: inbound + outbound)
    end

    meeting_time_seconds.each do |u|
      meeting = u.total
      res = result.find { |usr| usr.email == u.email }
      if res.nil?
        user = array_of_users.find { |usr| usr.email == u.email }
        result << Hashie::Mash.new(id: user.id, email: user.email, name: get_full_name(user), 'Read E-mails': 0, 'Sent E-mails': 0, 'Meetings': meeting, 'Attachments': 0 , total: meeting)
      else
        res.Meetings = meeting
        res.total += meeting
      end
    end

    attachment_counts.each do |u|
      attachment = u.attachment_count * User::ATTACHMENT_TIME_SEC # convert total number of attachments to approx. time in seconds
      res = result.find { |usr| usr.email == u.email }
      if res.nil?
        user = array_of_users.find { |usr| usr.email == u.email }
        result << Hashie::Mash.new(id: user.id, email: user.email, name: get_full_name(user), 'Read E-mails': 0, 'Sent E-mails': 0, 'Meetings': 0, 'Attachments': attachment , total: attachment)
      else
        res.Attachments = attachment
        res.total += attachment
      end
    end

    result.sort { |d1, d2| (d1.total != d2.total) ? d2.total <=> d1.total : d1.name.upcase <=> d2.name.upcase }
  end

  # This method should be called *after* all accounts, contacts, and users are processed & inserted.
  # each cluster within data creates a Project, even if multiple Projects map to same Account due to subdomain rollup!
  # avoid trying to load Activities from multiple clusters into same Project, since there may be common conversations between them
  def self.create_from_clusters(data, user_id, organization_id)
    project_subdomains = get_project_top_domain(data)
    project_domains = project_subdomains.map { |subdomain| get_domain_from_subdomain(subdomain) }.uniq
    accounts = Account.where(domain: project_domains, organization_id: organization_id)

    project_subdomains.each do |p|
      # find which Account this Project should belong to after getting domain from subdomain, Account for subdomain shouldn't exist
      p_account = accounts.find { |a| a.domain == get_domain_from_subdomain(p) }
      project = Project.new(name: p,
                           status: "Active",
                           category: "New Business",
                           created_by: user_id,
                           updated_by: user_id,
                           owner_id: user_id,
                           account: p_account,
                           is_public: true,
                           is_confirmed: false # This needs to be false during onboarding so it doesn't get read as real projects
                          ) unless p_account.nil?

      if project && project.save
        # Project members
        # assuming contacts and users have already been inserted, we just need to link them
        external_members, internal_members = get_project_members(data, p)
        contacts = Contact.where(email: external_members.map(&:address)).joins(:account).where("accounts.organization_id = ?", organization_id)
        users = User.where(email: internal_members.map(&:address), organization_id: organization_id)

        if Rails.env.development?
          onboarding_user = User.find(user_id)
          project.project_members.create(user: onboarding_user)
        end

        contacts.each do |c|
          project.project_members.create(contact: c)
        end

        users.each do |u|
          project.project_members.create(user: u)
        end

        # Upsert project conversations.
        Activity.load(get_project_conversations(data, p), project, true, user_id)

        # Upsert project meetings.
        ContextsmithService.load_calendar_from_backend(project, 1000)
      else
        if project.nil?
          puts "No project created because no account was found for  #{get_domain_from_subdomain(p)}"
        end
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

  # For an array of "project" id's, show # of days today is relative to the project close date
  def self.days_to_close(array_of_project_ids)
    days_to_close_per_project = Project.days_to_close_per_project(array_of_project_ids)
    Hash[days_to_close_per_project.map { |p| [p.id, p.days_to_close] }]
  end

  # convenience method to make input easier compared to time_shift
  def time_jump(date)
    puts "** #{self.inspect} contains no activities, skipping time_jump **" && return if activities.blank?
    latest_activity_date = activities.first.last_sent_date
    activities.each { |a| a.time_shift((date - latest_activity_date).round) }
  end

  ### method to batch update sent_date-related attributes of all activities in a project by a scalar value (in seconds)
  def time_shift(sec)
    activities.each { |a| a.time_shift(sec) }
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
      self.notifications.alerts.where("created_at < ? ", (days_ago_end).days.ago.in_time_zone(time_zone).to_date)
    else
      self.notifications.alerts.where(created_at: (days_ago_start).days.ago.in_time_zone(time_zone).to_date..(days_ago_end).days.ago.in_time_zone(time_zone).to_date)
    end
  end

  # Imports/updates all standard CS Opportunity fields from all mapped SFDC Opportunity fields for explicitly mapped CS and SFDC Opportunities.
  # Parameters:   client - connection to Salesforce
  #               opportunities - collection of CS Projects/Opportunities to process
  #               sfdc_fields_mapping - A list of [Mapped SFDC Opportunity field name, CS Opportunity field name] pairs
  # Returns:   A hash that represents the execution status/result. Consists of:
  #             status - "SUCCESS" if load was successful; otherwise, "ERROR" 
  #             result - if status == "ERROR", contains the title of the error
  #             detail - if status == "ERROR", contains the details of the error
    # TODO: Might want to move to SalesforceOpportunity.rb
  def self.update_standard_fields_from_sfdc(client: , opportunities: , sfdc_fields_mapping: )
    result = nil

    unless (client.nil? || opportunities.nil? || sfdc_fields_mapping.blank?)
      sfdc_fields_mapping = sfdc_fields_mapping.to_h
      sfdc_ids_mapping = opportunities.collect { |s| s.salesforce_opportunity.nil? ? nil : [s.salesforce_opportunity.salesforce_opportunity_id, s.id] }.compact  # a list of [linked SFDC sObject Id, CS Opportunity id] pairs
      sfdc_ids_mapping = sfdc_ids_mapping.to_h

      # puts "sfdc_fields_mapping: #{ sfdc_fields_mapping }"
      # puts "SFDC Opportunity field names: #{ sfdc_fields_mapping.keys }"
      # puts "sfdc_ids_mapping: #{ sfdc_ids_mapping }"
      # puts "SFDC Opportunity ids: #{ sfdc_ids_mapping.keys }"
      unless sfdc_ids_mapping.empty? 
        query_statement = "SELECT Id, " + sfdc_fields_mapping.keys.join(", ") + " FROM Opportunity WHERE Id IN ('" + sfdc_ids_mapping.keys.join("', '") + "')"
        query_result = SalesforceService.query_salesforce(client, query_statement)
        # puts "*** query: \"#{query_statement}\" ***"
        # puts "result (#{ query_result[:result].size if query_result[:result].present? } rows): #{ query_result }"

        if query_result[:status] == "SUCCESS"
          changed_values_hash_list = []
          query_result[:result].each do |r|
            # CS_UUID = sfdc_ids_mapping[r.Id] , SFDC_Id = r.Id
            sfdc_fields_mapping.each do |k,v|
              # k (SFDC field name) , v (CS field name), r[k] (SFDC field value)
              if r[k].is_a?(Restforce::Mash) # the value is a Salesforce sObject, so try to resolve each attribute of the sObject into a String of the fields delimited by commas
                sfdc_val = []
                r[k].each { |k,v| sfdc_val.push(v.to_s) if v.present? }
                sfdc_val = sfdc_val.join(", ")
              else
                sfdc_val = r[k]
              end
              changed_values_hash_list.push({ sfdc_ids_mapping[r.Id] => { v => sfdc_val } })
            end
          end
          # puts "changed_values_hash_list: #{ changed_values_hash_list }"

          changed_values_hash_list.each { |h| Project.update(h.keys, h.values) } # Make updates to project fields from the list of changed values
          result = { status: "SUCCESS" }
        else
          result = { status: "ERROR", result: query_result[:result], detail: query_result[:detail] + " query_statement=" + query_statement }
        end
      else  # No mapped CS Opportunities -> SFDC Opportunities
          result = { status: "SUCCESS" }  
      end
    else
      if client.nil?
        puts "** ContextSmith error: Parameter 'client' passed to Project.update_standard_fields_from_sfdc is invalid!"
        result = { status: "ERROR", result: "ContextSmith Error", detail: "A parameter passed to an internal function is invalid." }
      else
        # Ignores if other parameters were not passed properly to update_standard_fields_from_sfdc
        result = { status: "SUCCESS", result: "Warning: no fields updated.", detail: "No SFDC fields to import!" }
      end
    end

    result
  end

  # Imports/updates all custom CS Opportunity fields mapped to SFDC Opportunity fields for a single CS Opportunity/SFDC Opportunity pair.
  # Parameters:   client - connection to Salesforce
  #               project_id - CS project/opportunity id          
  #               sfdc_opportunity_id - SFDC opportunity sObjectId
  #               opportunity_custom_fields - ActiveRecord::Relation that represents the custom fields (CustomFieldsMetadatum) of the CS project/opportunity.
  # Returns:   A hash that represents the execution status/result. Consists of:
  #             status - "SUCCESS" if load was successful; otherwise, "ERROR" 
  #             result - if status == "ERROR", contains the title of the error
  #             detail - if status == "ERROR", contains the details of the error
  # TODO: Maybe make this a Project instance method.
  def self.update_custom_fields_from_sfdc(client: , project_id: , sfdc_opportunity_id: , opportunity_custom_fields: )
    result = nil

    unless (client.nil? || project_id.nil? || sfdc_opportunity_id.nil? || opportunity_custom_fields.blank?)
      opportunity_custom_field_names = opportunity_custom_fields.collect { |cf| cf.salesforce_field }

      query_statement = "SELECT " + opportunity_custom_field_names.join(", ") + " FROM Opportunity WHERE Id = '#{sfdc_opportunity_id}' LIMIT 1"
      query_result = SalesforceService.query_salesforce(client, query_statement)

      if query_result[:status] == "SUCCESS"
        sObj = query_result[:result].first
        opportunity_custom_fields.each do |cf|
          #csfield = CustomField.find_by(custom_fields_metadata_id: cf.id, customizable_uuid: project_id)
          #print "----> CS_fieldname=\"", cf.name, "\" SFDC_fieldname=\"", cf.salesforce_field, "\"\n"
          #print "   .. CS_fieldvalue=\"", csfield.value, "\" SFDC_fieldvalue=\"", sObj[cf.salesforce_field], "\"\n"
          new_value = sObj[cf.salesforce_field]
          if new_value.is_a?(Restforce::Mash) # the value is a Salesforce sObject, so try to resolve each attribute of the sObject into a String of the fields delimited by commas
            sfdc_val = []
            new_value.each { |k,v| sfdc_val.push(v.to_s) if v.present? }
            new_value = sfdc_val.join(", ")
          end
          CustomField.find_by(custom_fields_metadata_id: cf.id, customizable_uuid: project_id).update(value: new_value) # Make update to project custom field with value obtained in SFDC query
        end if sObj.present?
        result = { status: "SUCCESS" }
      else
        result = { status: "ERROR", result: query_result[:result], detail: query_result[:detail] + " opportunity_custom_field_names=" + opportunity_custom_field_names.to_s }
      end
    else
      if client.nil?
        puts "** ContextSmith error: Parameter 'client' passed to Project.update_custom_fields_from_sfdc is invalid!"
        result = { status: "ERROR", result: "ContextSmith Error", detail: "A parameter passed to an internal function is invalid." }
      else
        # Ignores if other parameters were not passed properly to update_custom_fields_from_sfdc
        result = { status: "SUCCESS", result: "Warning: no fields updated.", detail: "No SFDC fields to import!" }
      end
    end

    result
  end

  # Determines the SFDC entity level to which this opportunity (project) is linked ("Account" or "Opportunity"), then import Salesforce activities (ActivityHistory) from this SFDC entity into this opportunity.  Does not import previously-exported CS data residing on SFDC.  
  # Note: Does nothing if opportunity is not linked (status = SUCCESS, result = contains warning message). This process aborts upon encountering any error.
  # Additional Note:  This may called from ProjectsController#refresh !!
  # Parameters:   client - a valid SFDC connection
  #               from_lastmodifieddate (optional) - the minimum LastModifiedDate to begin import of SFDC Activities, timestamp exclusive; default, import with no minimum LastModifiedDate
  #               to_lastmodifieddate (optional) - the maximum LastModifiedDate to end import of SFDC Activities, timestamp inclusive; default, import with no maximum LastModifiedDate
  #               filter_predicates_h (optional) - a hash that contains keys "entity" and "activityhistory" that are predicates applied to the WHERE clause for SFDC Accounts/Opportunities and the ActivityHistory SObject, respectively. They will be directly injected into the SOQL (SFDC) query.
  #               limit (optional) - the max number of activity records to process
  # Returns:   A hash that represents the execution status/result. Consists of:
  #             status - string "SUCCESS" if successful, or "ERROR" otherwise
  #             result - if status == "SUCCESS", contains the result of the operation; otherwise, contains the title of the error
  #             detail - Contains any error or informational/warning messages.
  def load_salesforce_activities(client:, from_lastmodifieddate: nil, to_lastmodifieddate: nil, filter_predicates_h: nil, limit: nil)
    load_result = nil

    if salesforce_opportunity.blank? # CS Opportunity not linked to SFDC Opportunity
      if account.salesforce_accounts.present? # CS Opportunity linked to SFDC Account
        account.salesforce_accounts.each do |sfa|
          load_result = Activity.load_salesforce_activities(client: client, project: self, sfdc_id: sfa.salesforce_account_id, type: "Account", from_lastmodifieddate: from_lastmodifieddate, to_lastmodifieddate: to_lastmodifieddate, filter_predicates_h: filter_predicates_h, limit: limit)

          if load_result[:status] == "ERROR"
            error_detail = "Error while attempting to load activity from Salesforce Account \"#{sfa.salesforce_account_name}\" (sfdc_id='#{sfa.salesforce_account_id}') to CS Opportunity \"#{name}\" (opportunity_id='#{id}').  #{ load_result[:result] } Details: #{ load_result[:detail] }"
            return { status: "ERROR", result: load_result[:result], detail: error_detail }  # abort upon any error!
          end
        end
      else # CS Opportunity unlinked to any SFDC Account/Opportunity
        return { status: "SUCCESS", result: "CS Opportunity was not updated.", detail: "Warning: No SFDC entity linked to Opportunity!" }
      end
    else # CS Opportunity linked to SFDC Opportunity
      # Save at the Opportunity level
      load_result = Activity.load_salesforce_activities(client: client, project: self, sfdc_id: salesforce_opportunity.salesforce_opportunity_id, type: "Opportunity", from_lastmodifieddate: from_lastmodifieddate, to_lastmodifieddate: to_lastmodifieddate, filter_predicates_h: filter_predicates_h, limit: limit)

      if load_result[:status] == "ERROR"
        error_detail = "Error while attempting to load activity from Salesforce Opportunity \"#{salesforce_opportunity.name}\" (sfdc_id='#{salesforce_opportunity.salesforce_opportunity_id}') to CS Opportunity \"#{name}\" (opportunity_id='#{id}').  #{ load_result[:result] } Details: #{ load_result[:detail] }"
        return { status: "ERROR", result: load_result[:result], detail: error_detail }  # abort upon any error!
      end
    end

    return { status: "SUCCESS", result: load_result[:result], detail: nil }
  end

  def self.get_close_date_range(range_description)
    case range_description
      when CLOSE_DATE_RANGE[:ThisQuarter], CLOSE_DATE_RANGE[:ThisQuarterOpen]
        date = Time.current
        (date.beginning_of_quarter...date.end_of_quarter)
      when CLOSE_DATE_RANGE[:NextQuarter]
        date = Time.current.next_quarter
        (date.beginning_of_quarter...date.end_of_quarter)
      when CLOSE_DATE_RANGE[:LastQuarter]
        date = Time.current.prev_quarter
        (date.beginning_of_quarter...date.end_of_quarter)
      when CLOSE_DATE_RANGE[:QTD]
        (Time.current.beginning_of_quarter...Time.current)
      when CLOSE_DATE_RANGE[:YTD]
        (Time.current.beginning_of_year...Time.current)
      when CLOSE_DATE_RANGE[:Closed]
        (Time.at(0)...Time.current)
      when CLOSE_DATE_RANGE[:Open]
        (Time.current...100.years.from_now)
      else # use 'This Quarter' by default
        date = Time.current
        (date.beginning_of_quarter...date.end_of_quarter)
    end
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

  # Create all custom fields for a new Opportunity
  def create_custom_fields
    CustomFieldsMetadatum.where(organization:self.account.organization, entity_type: "Project").each { |cfm| CustomField.create(organization:self.account.organization, custom_fields_metadatum:cfm, customizable:self) }
  end
end
