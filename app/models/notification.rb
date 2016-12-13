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

include ActionView::Helpers::DateHelper

class Notification < ActiveRecord::Base

	belongs_to  :project, foreign_key: "project_id"
  belongs_to  :activity, foreign_key: "activity_id"
	belongs_to  :assign_to_user, :class_name => "User", foreign_key: "assign_to"
  belongs_to  :completed_by_user, :class_name => "User", foreign_key: "completed_by"

  scope :risks, -> { where category: CATEGORY[:Risk] }
  scope :open, -> { where is_complete: false }

  validates :project, presence: true

  CATEGORY = { Notification: 'Notification', Action: 'Smart Action', Todo: 'To-do', Risk: 'Alert', Opportunity: 'Opportunity' }

	def self.load(data, project, test=false, day_range=7)
		notifications = []
		data_hash = data.map { |hash| Hashie::Mash.new(hash) }

    current_time = Time.now.utc
    if test==true
      current_time = Time.new(2012,8,1).utc
    end

    puts current_time

    data_hash.each do |d|
	    d.conversations.each do |c|
	    	c.messages.each do |message|

          #save risk (message score < 0)
          if !message.sentimentItems.nil?
            load_risk_for_each_message(project.id, c.conversationId, message, test, day_range)
          end
      	end
	    end
	  end
	end

  def self.load_opportunity_for_stale_projects(project=nil)
    if project.nil?
      stale_projects = Project.find_stale_projects_30_days
    else
      stale_projects = project.is_stale_project_30_days
    end

    stale_projects.each do |p|
      a = Activity.order(last_sent_date: :desc).limit(1).find_by_project_id(p.id)

      if !a.nil?
        n = Notification.where(category: CATEGORY[:Opportunity], is_complete: false, project_id: p.id, conversation_id: a.backend_id)
        if n.empty?
          notification = Notification.new(category: CATEGORY[:Opportunity],
                                          name: "Check in with #{p.account.name}",
                                          description: "Last touch #{time_ago_in_words(Time.at(p.last_sent_date.to_i))} ago by #{p.from[0]['personal']}",
                                          message_id: '',
                                          project_id: p.id,
                                          conversation_id: a.backend_id,
                                          sent_date: '',
                                          original_due_date: '',
                                          remind_date: '',
                                          is_complete: false,
                                          assign_to: '',
                                          content_offset: -1,
                                          has_time: false,
                                          activity_id: a.id)

          notification.save
        end
      end
    end
  end

# add new risk(message score below 0)
  def self.load_risk_for_each_message(project_id, conversation_id, contextMessage, test=false, day_range=7)
    if Notification.find_by project_id: project_id, conversation_id: conversation_id, message_id: contextMessage.messageId, category: CATEGORY[:Risk]
      # avoid redundant
      return
    end

    score = contextMessage.sentimentItems[0].score.to_s[0,7].to_f

    if score >= -0.96
      # Ignore anything more positive than -0.96.
      return
    end

    sent_date = Time.at(contextMessage.sentDate).utc

    assign_to = User.find_by email: contextMessage.from[0].address
    if(assign_to.nil? and !contextMessage.to.nil? )
      assign_to = User.find_by email: contextMessage.to[0].address
    end

    assign_id = 0
    if(!assign_to.nil?)
        assign_id = assign_to.id
    end

    # get activity id. If no such activity exist in front end(could be caused by users deleting this activity), ignore this risk
    activity_id = -1
    a = Activity.find_by(category: "Conversation", backend_id: conversation_id, project_id: project_id)
    if !a.nil?
      activity_id = a.id
    else
      return
    end

    s = contextMessage.sentimentItems[0]
    context_start = s.sentence.beginOffset.to_i
    context_end = s.sentence.endOffset.to_i
    description = contextMessage.content.body[context_start..context_end]

    # check if older than previous two weeks, if true set auto complete
    current_time = Time.now.utc
    if test==true
      current_time = Time.new(2012,8,1).utc
    end

    is_complete = false
    completed_by = nil
    complete_date = nil
    sent_date = Time.at(contextMessage.sentDate).utc
    if (sent_date.utc < (current_time - day_range.day).utc)
      is_complete = true
      completed_by = "00000000-0000-0000-0000-000000000000"
      complete_date = sent_date
    end

    notification = Notification.new(category: CATEGORY[:Risk],
        name: contextMessage.subject,
        description: description,
        message_id: contextMessage.messageId,
        project_id: project_id,
        conversation_id: conversation_id,
        sent_date: sent_date,
        original_due_date: '',
        remind_date: '',
        is_complete: is_complete,
        assign_to: assign_id,
        content_offset: context_start,
        has_time: false,
        score: score,
        completed_by: completed_by,
        complete_date: complete_date,
        activity_id: activity_id)

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
