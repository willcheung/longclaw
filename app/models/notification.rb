# == Schema Information
#
# Table name: notifications
#
#  id                :integer          not null, primary key
#  category          :string           default("To-do"), not null
#  name              :string
#  description       :text
#  message_id        :string
#  project_id        :uuid
#  conversation_id   :string
#  sent_date         :datetime
#  original_due_date :datetime
#  remind_date       :datetime
#  is_complete       :boolean          default(FALSE), not null
#  has_time          :boolean          default(FALSE), not null
#  content_offset    :integer          default(-1), not null
#  complete_date     :datetime
#  assign_to         :uuid
#  completed_by      :uuid
#  label             :string
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  score             :float            default(0.0)
#  activity_id       :integer          default(-1)
#

class Notification < ActiveRecord::Base

  belongs_to  :project, foreign_key: "project_id"
  belongs_to  :activity, foreign_key: "activity_id"
  belongs_to  :assign_to_user, :class_name => "User", foreign_key: "assign_to"
  belongs_to  :completed_by_user, :class_name => "User", foreign_key: "completed_by"

  scope :risks, -> { where category: CATEGORY[:Alert] }
  scope :open, -> { where is_complete: false }

  validates :project, presence: true

  CATEGORY = { Notification: 'Notification', Action: 'Smart Action', Todo: 'To-do', Alert: 'Alert', Opportunity: 'Opportunity' }

  def self.load(data, project, test=false, day_range=7)
    alert_settings = RiskSetting.where(level: project.account.organization)
    
    neg_sentiment_setting = alert_settings.find { |as| as.metric == RiskSetting::METRIC[:NegSentiment] }
    pct_neg_sentiment_setting = alert_settings.find { |as| as.metric == RiskSetting::METRIC[:PctNegSentiment] }
    if neg_sentiment_setting.notify_task
      data_hash = data.map { |hash| Hashie::Mash.new(hash) }
      data_hash.each do |d|
        d.conversations.each do |c|
          c.messages.each do |message|
            if message.sentimentItems.present?
              load_alert_for_each_message(project.id, c.conversationId, message, neg_sentiment_setting, test, day_range)
            end
          end
        end
      end
    end

    # % Negative Sentiment Alerts
    if pct_neg_sentiment_setting.notify_task
      load_alert_for_pct_neg_sentiment(project, pct_neg_sentiment_setting, neg_sentiment_setting)
    end
  end

  def self.load_alert_for_days_inactive(organization)
    days_inactive_setting = RiskSetting.find_by(level: organization, metric: RiskSetting::METRIC[:DaysInactive])
    return unless days_inactive_setting.notify_task

    project_inactive_days = Project.where(account_id: organization.accounts.ids).joins(:activities).where.not(activities: { category: [Activity::CATEGORY[:Note], Activity::CATEGORY[:Alert]] }).group('projects.id').maximum('activities.last_sent_date')
    project_inactive_days.each { |pid, last_sent_date| project_inactive_days[pid] = Time.current.to_date.mjd - last_sent_date.to_date.mjd } # convert last_sent_date to days inactive
    project_inactive_days.reject! { |pid, days_inactive| days_inactive < days_inactive_setting.medium_threshold }

    stale_projects = Project.where(id: project_inactive_days.keys)
    stale_projects.each do |p|
      days_inactive = project_inactive_days[p.id]
      level = days_inactive > days_inactive_setting.high_threshold ? "High" : "Medium"
      project_owner = p.owner_id || '00000000-0000-0000-0000-000000000000'
      name = "Inactive for #{days_inactive} days!"
      description = "Days Inactive for #{p.name} exceeded #{level} Threshold at #{days_inactive} days."

      last_activity = p.activities.where.not(category: Activity::CATEGORY[:Note]).first
      if last_activity.category == Activity::CATEGORY[:Conversation]
        message_id = last_activity.email_messages.last.messageId
        conversation_id = last_activity.backend_id
      else
        message_id = nil
        conversation_id = nil
      end

      # if last_activity is a days inactive alert, the current days inactive streak is running, update it
      if last_activity.category == Activity::CATEGORY[:Alert] && last_activity.email_messages.first && last_activity.email_messages.first.days_inactive?
        alert_activity = last_activity
      # otherwise, make a new days inactive alert on timeline
      else
        alert_activity = p.activities.new(
          posted_by: project_owner,
          category: Activity::CATEGORY[:Alert],
          is_public: true
        )
      end
      alert_activity.update(
        title: name,
        note: description,
        email_messages: [{days_inactive: days_inactive}],
        last_sent_date: Time.now.utc,
        last_sent_date_epoch: Time.now.utc.to_i
      )

      # Create/Update the notification with appropriate Activity id
      p.notifications.find_or_initialize_by(
        category: CATEGORY[:Alert],
        label: "DaysInactive",
        is_complete: false,
        completed_by: nil, # so we don't overwrite completed tasks
        complete_date: nil # same here
      ).update(
        name: name,
        description: description,
        assign_to: project_owner,
        message_id: message_id,
        conversation_id: conversation_id,
        activity_id: last_activity.id
      )
    end
  end

  def self.load_alert_for_pct_neg_sentiment(project, alert_setting, sentiment_setting)
    engagement_volume = project.conversations.sum('jsonb_array_length(email_messages)')
    neg_sentiments = project.conversations.select(:id, :backend_id, "(jsonb_array_elements(jsonb_array_elements(email_messages)->'sentimentItems')->>'score')::float AS sentiment_score, jsonb_array_elements(email_messages)->>'messageId' AS message_id")
      .each { |a| a.sentiment_score = scale_sentiment_score(a.sentiment_score) }.select { |a| a.sentiment_score > sentiment_setting.high_threshold }
    pct_neg_sentiment = neg_sentiments.count.to_f/engagement_volume

    return if pct_neg_sentiment < alert_setting.medium_threshold
    level = pct_neg_sentiment < alert_setting.high_threshold ? "Medium" : "High"

    last_neg_sentiment_activity = neg_sentiments.first
    project_owner = project.owner_id || '00000000-0000-0000-0000-000000000000'
    name = "% Negative Sentiment threshold exceeded!"
    description = "% Negative Sentiment for #{project.name} exceeded #{level} Threshold at #{(pct_neg_sentiment*100).round(1)}%"

    # Create an event in Timeline
    project.activities.create(
      posted_by: project_owner,
      category: Activity::CATEGORY[:Alert],
      email_messages: [{pct_neg_sentiment: (pct_neg_sentiment*100).round(1)}],
      is_public: true,
      title: name,
      note: description,
      last_sent_date: Time.now.utc,
      last_sent_date_epoch: Time.now.utc.to_i
    )

    project.notifications.find_or_initialize_by(
      category: CATEGORY[:Alert],
      label: "PctNegSentiment",
      is_complete: false,
      completed_by: nil,
      complete_date: nil
    ).update(
      name: name,
      description: description,
      assign_to: project_owner,
      message_id: nil,
      conversation_id: nil,
      activity_id: -1
    )
  end

  def self.load_alert_for_each_message(project_id, conversation_id, contextMessage, alert_setting, test=false, day_range=7)
    # avoid redundant
    return if Notification.find_by project_id: project_id, conversation_id: conversation_id, message_id: contextMessage.messageId, category: CATEGORY[:Alert]

    # get activity id. If no such activity exist in front end(could be caused by users deleting this activity), ignore this risk
    activity = Activity.find_by(category: Activity::CATEGORY[:Conversation], backend_id: conversation_id, project_id: project_id)
    return if activity.blank?

    score = contextMessage.sentimentItems[0].score.to_f
    scaled_score = scale_sentiment_score(score)
    # Ignore anything less than alert setting high threshold.
    return if scaled_score < alert_setting.high_threshold 

    sent_date = Time.at(contextMessage.sentDate).utc

    assign_to = User.find_by email: contextMessage.from[0].address
    assign_to = User.find_by email: contextMessage.to[0].address if assign_to.nil? && contextMessage.to
    assign_to = assign_to.blank? ? nil : assign_to.id

    s = contextMessage.sentimentItems[0]
    context_start = s.sentence.beginOffset.to_i
    context_end = s.sentence.endOffset.to_i
    description = s.sentence.text

    # check if older than previous two weeks, if true set auto complete
    current_time = Time.current.utc
    current_time = Time.new(2012,8,1).utc if test

    is_complete = false
    complete_date = nil
    sent_date = Time.at(contextMessage.sentDate).utc
    if (sent_date < (current_time - day_range.day))
      is_complete = true
      complete_date = sent_date
    end

    notification = Notification.new(
      category: CATEGORY[:Alert],
      label: "NegSentiment",
      name: contextMessage.subject,
      description: description,
      message_id: contextMessage.messageId,
      project_id: project_id,
      conversation_id: conversation_id,
      sent_date: sent_date,
      is_complete: is_complete,
      assign_to: assign_to,
      content_offset: context_start,
      has_time: false,
      score: scaled_score,
      complete_date: complete_date,
      activity_id: activity.id
    )

    notification.save
  end

  def self.find_project_and_user(array_of_project_ids, wherestatement="")

    query = ""
    if !wherestatement.empty?
      query = "SELECT notifications.*, users.first_name, users.last_name FROM notifications
      LEFT JOIN users ON users.id = notifications.assign_to
      WHERE notifications.project_id IN ('#{array_of_project_ids.join("','")}') AND #{wherestatement} ORDER BY created_at DESC"
    else
      query = "SELECT notifications.*, users.first_name, users.last_name FROM notifications
      LEFT JOIN users ON users.id = notifications.assign_to
      WHERE notifications.project_id IN ('#{array_of_project_ids.join("','")}') AND is_complete = FALSE ORDER BY created_at DESC"
    end

    Notification.find_by_sql(query)
  end

  # Checks whether notification is visible to user based on Activity
  def is_visible_to(user)
    activity.blank? || activity.is_visible_to(user)
  end
end
