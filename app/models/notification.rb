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
#

include ActionView::Helpers::DateHelper

class Notification < ActiveRecord::Base

	belongs_to  :project, foreign_key: "project_id"
	belongs_to  :activity, foreign_key: "conversation_id"
	belongs_to  :assign_to_user, :class_name => "User", foreign_key: "assign_to"
  belongs_to  :completed_by_user, :class_name => "User", foreign_key: "completed_by"

  CATEGORY = { Notification: 'Notification', Action: 'Smart Action', Todo: 'To-do', Risk: 'Risk', Opportunity: 'Opportunity' }

	def self.load(data, project, test=false)
		notifications = []
		data_hash = data.map { |hash| Hashie::Mash.new(hash) }

    current_time = Time.now.utc
    if test==true
      current_time = Time.new(2012,8,1).utc
    end

    puts current_time

    data_hash.each do |d|
	    d.conversations.each do |c|
	    	c.contextMessages.each do |contextMessage|

          sent_date = Time.at(contextMessage.sentDate).utc
          if(sent_date.utc < (current_time - 7.day).utc)
              # puts "skip this one"
              next
            end

          if contextMessage.temporalItems.nil?
            #puts "no task"
            next
          end

          assign_to = User.find_by email: contextMessage.from[0].address
          if(assign_to.nil? and !contextMessage.to.nil? )
            assign_to = User.find_by email: contextMessage.to[0].address
          end

          assign_id = 0
          if(!assign_to.nil?)
              assign_id = assign_to.id
          end

          contextMessage.temporalItems.each do |t|
            context_start = t.taskAnnotation.beginOffset.to_i
            context_end = t.taskAnnotation.endOffset.to_i
            description = contextMessage.content.body[context_start..context_end]
            o_due_date = Time.at(t.resolvedDates[0]).utc
            # rake have no idea about local time zone, Time.zone.at will just return the time zone in application.rb
            # so can't covert to user local time.
            # don't deal with has_time = false (previously we change the hour and min to 0)
            # just use back end garbage time.
            has_time = t.hasTime.to_s
            remind_date = o_due_date.yesterday.utc

            if Notification.find_by project_id: project.id, conversation_id: c.conversationId, message_id: contextMessage.messageId, content_offset: context_start 
              # avoid redundant
              next
            end

    	      notification = Notification.new(category: 'Smart Action',
      	      	name: contextMessage.subject,
      	      	description: description,
      	        message_id: contextMessage.messageId,
      	        project_id: project.id,
      	        conversation_id: c.conversationId,
                sent_date: sent_date,
      	        original_due_date: o_due_date,
      	        remind_date: remind_date,
      	        is_complete: false,
      	        assign_to: assign_id,
                content_offset: context_start,
                has_time: has_time)

    	      notification.save
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
      notification = Notification.new(category: 'Opportunity',
                                      name: "Check in with #{p.account.name}",
                                      description: "Last touch #{time_ago_in_words(Time.at(p.last_sent_date.to_i))} ago by #{p.from[0]['personal']}",
                                      message_id: '',
                                      project_id: p.id,
                                      conversation_id: '',
                                      sent_date: '',
                                      original_due_date: '',
                                      remind_date: '',
                                      is_complete: false,
                                      assign_to: '',
                                      content_offset: -1,
                                      has_time: false)

      notification.save
    end
  end

  def self.find_project_and_user(array_of_project_ids)

    query = <<-SQL
      SELECT notifications.*, users.first_name, users.last_name FROM notifications LEFT JOIN users ON users.id = notifications.assign_to where project_id in ('#{array_of_project_ids.join("','")}') AND notifications.is_complete = false ORDER BY original_due_date DESC
    SQL

    Notification.find_by_sql(query)
  end
end
