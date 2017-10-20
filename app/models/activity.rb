 # == Schema Information
#
# Table name: activities
#
#  id                   :integer          not null, primary key
#  category             :string           not null
#  title                :string           not null
#  note                 :text             default(""), not null
#  is_public            :boolean          default(TRUE), not null
#  backend_id           :string
#  last_sent_date       :datetime
#  last_sent_date_epoch :string
#  from                 :jsonb            default([]), not null
#  to                   :jsonb            default([]), not null
#  cc                   :jsonb            default([]), not null
#  email_messages       :jsonb            default([]), not null
#  project_id           :uuid             not null
#  posted_by            :uuid             not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  is_pinned            :boolean          default(FALSE)
#  pinned_by            :uuid
#  pinned_at            :datetime
#  rag_score            :integer
#
# Indexes
#
#  index_activities_on_category_and_backend_id_and_project_id  (category,backend_id,project_id) UNIQUE
#  index_activities_on_email_messages                          (email_messages)
#  index_activities_on_project_id                              (project_id)
#
require 'action_view'
include ActionView::Helpers::DateHelper  #for time_ago_in_words
### TODO: refactor show_email_body so that it does not depend on simple_format which must be included from ActionView module (separate Controller from Views)
include ActionView::Helpers::TextHelper  # for simple_format
include ActionView::Helpers::SanitizeHelper   # for strip_tags

class Activity < ActiveRecord::Base
  include PgSearch

  belongs_to :user, class_name: "User", foreign_key: "posted_by"
  belongs_to :project
  belongs_to :oauth_user
  has_many :comments, dependent: :destroy
  has_many :notifications_all, class_name: 'Notification', dependent: :destroy
  has_many :notifications, -> { non_attachments }
  has_many :attachments, -> { attachments }, class_name: 'Notification'

  scope :pinned, -> { where is_pinned: true }
  scope :last_active_on, -> { maximum "last_sent_date" }
  scope :conversations, -> { where category: CATEGORY[:Conversation] }
  scope :notes, -> { where category: CATEGORY[:Note] }
  scope :meetings, -> { where category: CATEGORY[:Meeting] }
  scope :from_yesterday, -> { where last_sent_date: Time.current.yesterday.midnight..Time.current.yesterday.end_of_day }
  scope :from_lastweek, -> { where last_sent_date: 1.week.ago.midnight..Time.current.yesterday.end_of_day }
  scope :next_week, -> { where last_sent_date: Time.current..1.week.from_now.midnight }
  scope :reverse_chronological, -> { order last_sent_date: :desc }
  scope :visible_to, -> (user_email) { where "is_public IS TRUE OR \"from\" || \"to\" || \"cc\" @> '[{\"address\":\"#{user_email}\"}]'::jsonb" }
  scope :latest_rag_score, -> { notes.where.not( rag_score: nil) }

  acts_as_commentable

  pg_search_scope :search_note,
                  :against => [:note, :title],
                  :using => {
                      :tsearch => {:dictionary => "english"}
                  }

  CS_ACTIVITY_SFDC_EXPORT_SUBJ_PREFIX = "CS"
  CS_ACTIVITY_SFDC_EXPORT_DESC_PREFIX = "(imported from ContextSmith) ——"
  CATEGORY = { Conversation: 'Conversation', Note: 'Note', Meeting: 'Meeting', JIRA: 'JIRA Issue', Salesforce: 'Salesforce Activity', Zendesk: 'Zendesk Ticket', Alert: 'Alert', Basecamp2: 'Basecamp2', Pinned: 'Key Activity' }

  def self.load(data, project, save_in_db=true, user_id='00000000-0000-0000-0000-000000000000')
    activities = []
    val = []

    data_hash = data.map { |hash| Hashie::Mash.new(hash) }

    data_hash.each do |d|
      d.conversations.each do |c|
        is_public_flag = true
        c.messages.last.isPrivate ? is_public_flag = false : true  # check if last message is private

        # if last message is a private message (one to one email), check user settings
        if is_public_flag==false
          sender = User.find_by(email: c.messages.last.from[0]['address'])
          if !sender.nil? and !sender.blank?
            is_public_flag = !sender.mark_private
          elsif !c.messages.last.to.nil?
            to = User.find_by(email: c.messages.last.to[0]['address'])
            if !to.nil? and !to.blank?
              is_public_flag = !to.mark_private
            end
          elsif !c.messages.last.cc.nil?
            cc = User.find_by(email: c.messages.last.cc[0]['address'])
            if !cc.nil? and !cc.blank?
              is_public_flag = !cc.mark_private
            end
          end
        end

        val << "('#{user_id}', '#{project.id}', '#{CATEGORY[:Conversation]}', #{Activity.sanitize(c.subject)}, #{is_public_flag}, '#{c.conversationId}', '#{Time.at(c.lastSentDate)}', '#{c.lastSentDate}',
                   #{Activity.sanitize(c.messages.last.from.to_json)},
                   #{Activity.sanitize(c.messages.last.to.to_json)},
                   #{Activity.sanitize(c.messages.last.cc.to_json)},
                   #{Activity.sanitize(c.messages.to_json)},
                   '#{Time.now}', '#{Time.now}')"

        # Create activities object
        activities << Activity.new(
            posted_by: user_id,
            project_id: project.id,
            category: CATEGORY[:Conversation],
            title: c.subject,
            note: '',
            is_public: is_public_flag,
            backend_id: c.conversationId,
            last_sent_date: Time.at(c.lastSentDate),
            last_sent_date_epoch: c.lastSentDate,
            from: c.messages.last.from, # take from last message
            to: c.messages.last.to,     # take from last message
            cc: c.messages.last.cc,     # take from last message
            email_messages: c.messages
        )
      end
    end

    insert = 'INSERT INTO "activities" ("posted_by", "project_id", "category", "title", "is_public", "backend_id", "last_sent_date", "last_sent_date_epoch", "from", "to", "cc", "email_messages", "created_at", "updated_at") VALUES'
    on_conflict = 'ON CONFLICT (category, backend_id, project_id) DO UPDATE SET last_sent_date = EXCLUDED.last_sent_date, last_sent_date_epoch = EXCLUDED.last_sent_date_epoch, updated_at = EXCLUDED.updated_at, email_messages = EXCLUDED.email_messages'
    values = val.join(', ')

    if !val.empty? and save_in_db
      Activity.transaction do
        # Insert activities into database
        Activity.connection.execute([insert,values,on_conflict].join(' '))
      end
    end

    return activities
  end

  #
  def self.load_calendar(data, project, save_in_db=true, user_id='00000000-0000-0000-0000-000000000000')
    events = []
    val = []

    data_hash = data.map { |hash| Hashie::Mash.new(hash) }

    data_hash.each do |d|
      d.conversations.each do |c|
        event = c.messages.first
        # time adjustment for recurring meetings which have an end time before the start time
        end_epoch = event.endTime
        if c.lastSentDate > end_epoch
          start_time = Time.at(c.lastSentDate).utc
          end_time = Time.at(end_epoch).utc
          end_time = start_time.midnight + end_time.hour.hours + end_time.min.minutes
          end_time += 1.day if start_time > end_time
          end_epoch = end_time.to_i
        end
        # store miscellaneous data in email_messages column
        messages_data = [{ created: event.createdTime, updated: event.updatedTime, end_epoch: end_epoch }]

        val << "('#{user_id}', '#{project.id}', '#{CATEGORY[:Meeting]}', #{Activity.sanitize(c.subject)}, true,
                 '#{c.conversationId}', '#{Time.at(c.lastSentDate).utc}', '#{c.lastSentDate}',
                  #{Activity.sanitize(event.from.to_json)},
                  #{Activity.sanitize(event.to.to_json)},
                  #{Activity.sanitize(messages_data.to_json)},
                 '#{Time.now}', '#{Time.now}')"


        # Create events object
        events << Activity.new(
            posted_by: user_id,
            project_id: project.id,
            category: CATEGORY[:Meeting],
            title: c.subject,
            note: '',
            is_public: true,
            backend_id: c.conversationId,
            last_sent_date: Time.at(c.lastSentDate).utc,
            last_sent_date_epoch: c.lastSentDate,
            from: event.from,
            to: event.to,
            email_messages: messages_data
        )
      end
    end

    insert = 'INSERT INTO "activities" ("posted_by", "project_id", "category", "title", "is_public", "backend_id", "last_sent_date", "last_sent_date_epoch", "from", "to", "email_messages", "created_at", "updated_at") VALUES'
    on_conflict = 'ON CONFLICT (category, backend_id, project_id) DO UPDATE SET last_sent_date = EXCLUDED.last_sent_date, last_sent_date_epoch = EXCLUDED.last_sent_date_epoch, updated_at = EXCLUDED.updated_at, email_messages = EXCLUDED.email_messages'
    values = val.join(', ')

    if !val.empty? and save_in_db
      Activity.transaction do
        # Insert events into database
        Activity.connection.execute([insert,values,on_conflict].join(' '))
      end
    end

    return events
  end

  # Copies/imports Salesforce activities (ActivityHistory) in the specified SFDC Account or Opportunity into the specified CS opportunity (project).  Does not import previously-exported CS data residing on SFDC.
  # Parameters:   client - a valid SFDC connection
  #               project - the CS opportunity into which to load the SFDC activity
  #               sfdc_id - the id of the SFDC Account/Opportunity from which to load the activity
  #               type - the SFDC entity level ("Account" or "Opportunity") from which to load activities
  #               filter_predicates (optional) - a hash that contains keys "entity" and "activityhistory" that are predicates applied to the WHERE clause for SFDC Accounts/Opportunities, and the ActivityHistory SObject, respectively. They will be directly injected into the SOQL (SFDC) query.
  #               limit (optional) - the max number of activity records to process
  # Returns:   A hash that represents the execution status/result. Consists of:
  #             status - string "SUCCESS" if successful, or "ERROR" otherwise
  #             result - if status == "SUCCESS", contains the result of the operation; otherwise, contains the title of the error
  #             detail - Contains any error or informational/warning messages.
  def self.load_salesforce_activities(client, project, sfdc_id, type="Account", filter_predicates=nil, limit=200)
    val = []
    result = nil

    # return { status: "ERROR", result: "Simulated SFDC error", detail: "Simulated detail" }

    if filter_predicates["entity"] == ""
      entity_predicate = ""
    else
      entity_predicate = "AND (" + filter_predicates["entity"] + ")"
    end
    if filter_predicates["activityhistory"] == ""
      activityhistory_predicate = ""
    else
      activityhistory_predicate = "AND (" + filter_predicates["activityhistory"] + ")"
    end

    # Note: we avoid importing exported CS data residing on SFDC
    if type == "Account"
      query_statement = "SELECT Name, (SELECT Id, ActivityDate, ActivityType, ActivitySubtype, Owner.Name, Owner.Email, Subject, Description, Status, LastModifiedDate FROM ActivityHistories WHERE (NOT(ActivitySubType = 'Task' AND (#{ get_CS_export_prefix_SOQL_predicate_string }))) #{activityhistory_predicate} limit #{limit}) FROM Account WHERE Id='#{sfdc_id}' #{entity_predicate}"  
    elsif type == "Opportunity"
      query_statement = "SELECT Name, (SELECT Id, ActivityDate, ActivityType, ActivitySubtype, Owner.Name, Owner.Email, Subject, Description, Status, LastModifiedDate FROM ActivityHistories WHERE (NOT(ActivitySubType = 'Task' AND (#{ get_CS_export_prefix_SOQL_predicate_string }))) #{activityhistory_predicate} limit #{limit}) FROM Opportunity WHERE Id='#{sfdc_id}' #{entity_predicate}"
    end
    
    #puts "query_statement: #{ query_statement }"
    query_result = SalesforceService.query_salesforce(client, query_statement)

    # puts "\t\t ***** query_result= #{query_result} nil?=#{query_result.nil?}"
    if query_result[:status] == "SUCCESS"
      # puts "\t\t ***** query_result[:result].first= #{query_result[:result].first} nil?=#{query_result[:result].first.nil?}"
      unless query_result[:result].first.nil?
        query_result[:result].first.each do |a|
          if a.first == "ActivityHistories"
            if !a.second.nil? # if any ActivityHistory
              a.second.each do |c|
                owner = { "address": Activity.sanitize(c.Owner.Email)[1, c.Owner.Email.length], "personal": Activity.sanitize(c.Owner.Name)[1, c.Owner.Name.length] }
                val << "('00000000-0000-0000-0000-000000000000', '#{project.id}', '#{CATEGORY[:Salesforce]}', #{Activity.sanitize(c.Subject)}, true, '#{c.Id}', '#{c.LastModifiedDate}', '#{DateTime.parse(c.LastModifiedDate).to_i}',
                         '[#{owner.to_json}]',
                         '[]',
                         '[]',
                         #{Activity.sanitize([c].to_json)},
                         #{c.Description.nil? ? '\'\'' : Activity.sanitize(c.Description)},
                         '#{Time.now}', '#{Time.now}')"
              end
            end
          end
        end

        insert = 'INSERT INTO "activities" ("posted_by", "project_id", "category", "title", "is_public", "backend_id", "last_sent_date", "last_sent_date_epoch", "from", "to", "cc", "email_messages", "note", "created_at", "updated_at") VALUES'
        on_conflict = 'ON CONFLICT (category, backend_id, project_id) DO UPDATE SET title = EXCLUDED.title, note = EXCLUDED.note, email_messages = EXCLUDED.email_messages, last_sent_date = EXCLUDED.last_sent_date, last_sent_date_epoch = EXCLUDED.last_sent_date_epoch, updated_at = EXCLUDED.updated_at'
        values = val.join(', ')

        if !val.empty?
          Activity.transaction do
            # Insert activities into database
            Activity.connection.execute([insert,values,on_conflict].join(' '))
          end
        end
        #puts "***** Result of:", query_statement
        #puts "-> # of rows UPSERTed into Activities = #{val.count} total *****"
        if val.count > 0
          result = { status: "SUCCESS", result: "No. of rows UPSERTed into Activities = #{val.count}", detail: "#{ query_result[:detail] }" }
        else
          result = { status: "SUCCESS", result: "No rows inserted into Activities.", detail: "Warning: No SFDC activity to import!" }
        end
      else
        puts "*** Salesforce error: SFDC query status=SUCCESS, but no valid result was returned! Check for invalid SFDC entity Ids in Salesforce_opportunity and Salesforce_account tables, or user's access level.  Detail: query_result= #{query_result[:result]} \t query_result[:result].first= #{query_result[:result].first}"  # Temporary diagnostic console message to determine a SFDC (permission?) issue 
        result = { status: "ERROR", result: "No rows inserted into Activities.", detail: "Warning: SFDC query returned successfully, but an invalid result was returned from Salesforce!  This can occur when Salesforce cannot find the SFDC sObject Id specified by ContextSmith; please verify that a valid SFDC account/opportunity is linked to this opportunity.  It may also be possible your SFDC user may not have the proper access permissions; please verify with your Salesforce Administrator that you have access such as to the ActivityHistory/Task relation." }
      end
    else  # SFDC query failure
      result = { status: "ERROR", result: query_result[:result], detail: "#{ query_result[:detail] } Query: #{ query_statement }" }
    end

    result
  end

  # Bulk delete CS Activities found in a SFDC Account or Opportunity (in its ActivityHistory).
  # Parameters:   client - SFDC connection
  #               type - SFDC entity type: 'Account' or 'Opportunity'
  #               from_date (optional) - the start date of a date range (e.g., "2018-01-01")
  #               to_date (optional) - the end date of a date range (e.g., "2018-01-01")
  # Notes:  SFDC type formats:  dateTime = "2018-01-01T00:00:00z",  date = "2018-01-01"
  def self.delete_cs_activities(client, type="Account", from_date=nil, to_date=nil)
    delete_tasks_query_stmt = "select Id FROM Task WHERE TaskSubType = 'Task' AND Status = 'Completed' AND (#{ get_CS_export_prefix_SOQL_predicate_string })"
    delete_tasks_query_stmt += " AND ActivityDate >= #{from_date}" if from_date.present?
    delete_tasks_query_stmt += " AND ActivityDate <= #{to_date}" if to_date.present?
    puts "Deleting all existing, completed SFDC Tasks that were exported from ContextSmith on Salesforce.  SFDC query=\'#{delete_tasks_query_stmt}\'...."
    query_result = SalesforceService.query_salesforce(client, delete_tasks_query_stmt)
    #tasks = client.query(delete_tasks_query_stmt)

    if query_result[:status] == "SUCCESS"
      query_result[:result].each { |t| t.destroy }
      puts "Deletion completed!"
    else  # SFDC query failure
      puts "Error occured while attempted to delete SFDC Tasks on Salesforce.  #{ query_result[:result] } Detail: #{ query_result[:detail] } "  # proprogate query to caller
    end
  end

  # Bulk export CS Activities to a SFDC Account or Opportunity (as completed Tasks in ActivityHistory). Ignores imported SFDC activity residing locally in CS.
  # Parameters:   client - SFDC connection
  #               project - the CS opportunity from which to export
  #               sfdc_id - the id of the SFDC Account/Opportunity to which this exports the CS activity
  #               type - to specify exporting into an SFDC "Account" or "Opportunity"
  #               filter_predicates (optional) - a hash that contains keys "entity" and "activityhistory" that are predicates applied to the WHERE clause for SFDC Accounts/Opportunities, and the ActivityHistory SObject, respectively. They will be directly injected into the SOQL (SFDC) query.
  # Returns:   A hash that represents the execution status/result. Consists of:
  #             status - "SUCCESS" if operation is successful with no errors (activities exported or no activities to export); ERROR" if any error occurred during the operation (including partial successes)
  #             result - a list of sObject SFDC id's that were successfully created in SFDC, or an empty list if none were created.
  #             detail - a list of errors or informational/warning messages.
  def self.export_cs_activities(client, project, sfdc_id, type="Account", from_date=nil, to_date=nil)
    result = { status: "SUCCESS", result: [], detail: [] }
    # return { status: "ERROR", result: "Simulated SFDC error", detail: "Simulated detail" }

    project.activities.each do |a|
      # First, put together all the fields of the activity, for preparation of creating a (completed) SFDC Task.
      subject = CS_ACTIVITY_SFDC_EXPORT_SUBJ_PREFIX + " " + a.category + ": "+ a.title
      description = a.category + " activity (imported from ContextSmith) ——\n"
      activity_date = Time.zone.at(a.last_sent_date).strftime("%Y-%m-%d")
      if a.category == Activity::CATEGORY[:Conversation]
          subject = CS_ACTIVITY_SFDC_EXPORT_SUBJ_PREFIX + " E-mail: "+ a.title
          description = "E-mail activity #{CS_ACTIVITY_SFDC_EXPORT_DESC_PREFIX}\n"
          #activity_date = Time.zone.at(m.sentDate).strftime("%b %d")
          description += "Description:  \"#{ a.title }:\"  #{ get_conversation_member_names(a.from, a.to, a.cc) }"
          description += !a.is_public ? "  (private)\n" : "\n"
          a.email_messages.each do |m|
            description += "—————————————————————————\n"
            description += "Sender/Recipients: " + (m.from[0].personal.nil? ? m.from[0].address : m.from[0].personal) + " to " + get_conversation_member_names([], m.to, m.cc, 'All') + "\n"
            description += "Date: " + Time.zone.at(m.sentDate).strftime("%b %d") +"\n"
            description += "Content: " + strip_tags(self.smart_email_body(m, @users_reverse.present?)) + "\n"
          end
      elsif a.category == Activity::CATEGORY[:Note]
          description += "Description:  #{ self.get_full_name(a.user) } wrote:\n"
          description += a.note.present? ? a.note : self.rag_note(a.rag_score.to_i)
      elsif a.category == Activity::CATEGORY[:Meeting] 
          description += "Description:  #{ a.title }"
          description += !a.is_public ? "  (private)\n" : "\n"
          description += "Time: #{ self.get_calendar_interval(a) }\n"
          description += "Meeting Organizer: #{ a.from[0].personal ? a.from[0].personal : a.from[0].address }\n"
          description += "Attendees: #{ self.get_calendar_member_names(a.to) }\n"
      elsif a.category == Activity::CATEGORY[:JIRA]
          description += "Description:  #{ a.note }\n"
          description += " #{ pluralize(a.email_messages.first.issue.fields.comment.total - 1, 'older comment') } on JIRA" if a.email_messages.first.issue.fields.comment.total > 1

          a.email_messages.first.issue.fields.comment.comments.each { |c| description += "\n#{ c.author.displayName } added a comment: #{ c.body }\n" }
          # "- #{time_ago_in_words(c.updated.to_time)} ago"
      elsif a.category == Activity::CATEGORY[:Zendesk]
          description += "Description:  \"#{ a.title }:\"  #{ get_conversation_member_names(a.from, a.to, a.cc) }  #{ a.email_messages.first.status }"
          description += !a.is_public ? "  (private)\n" : "\n"

          a.email_messages.first.comments.each do |c|
            description += "#{ c.author } added a comment - #{ c.created_at }\n"
            description += "Content: #{ strip_tags(simple_format(c.text)) }\n"
           end
      elsif a.category == Activity::CATEGORY[:Basecamp2]
          description += "Description:  \"#{ a.title }\"  #{ get_conversation_member_names(a.from, a.to, a.cc) }"
          description += !a.is_public ? "  (private)\n" : "\n"
          a.email_messages.reverse.each do |c|
            if c.eventable
              description += "—————————————————————————\n"
              if c.action == 'commented on'
                description += "#{ c.creator.name } added a comment - #{ c.created_at.to_date }\n"
              else
                description += "#{ c.creator.name } created discussion - #{ c.created_at.to_date }\n"
              end
              description += "Content: #{ strip_tags(simple_format(c[:excerpt])) }\n"
            end
          end
      elsif a.category == Activity::CATEGORY[:Alert]
          description += "Description:  #{ a.title }\n"
          description += a.note + "\n"
      else
          next # if any other Activity type (e.g., Salesforce), skip to the next Activity!
      end

      # Second, put the fields into a hash object.
      sObject_meta = { id: sfdc_id, type: type }
      sObject_fields = { activity_date: Time.zone.at(a.last_sent_date).strftime("%Y-%m-%d"), subject: subject, priority: 'Normal', description: description }
      # puts "----> sObject_meta:\n #{sObject_meta}\n"
      # puts "----> sObject_fields:\n #{sObject_fields}\n"

      # Finally, send information in hashes to be created as (completed) Tasks in SFDC.
      update_result = SalesforceService.update_salesforce(client: client, update_type: "activity", sObject_meta: sObject_meta, sObject_fields: sObject_fields)

      if update_result[:status] == "SUCCESS"  # unless failed Salesforce query
        puts "-> a SFDC Task was created from a ContextSmith activity. New Task Id='#{ update_result[:result] }'."
        # Don't set result[:status] back to SUCCESS if the export of a previous activity had an ERROR!
        result[:result] << update_result[:result]
        result[:detail] << update_result[:detail]
      else  # Salesforce update failure
        # puts "** #{ update_result[:result] } Details: #{ update_result[:detail] }."
        result[:status] = "ERROR"
        result[:result] << update_result[:result]
        result[:detail] << update_result[:detail] + " sObject_fields=#{ sObject_fields }"
      end
    end # project.activities.each do

    result
  end

  #
  def self.load_basecamp2_activities(e, project, user, project_id)
    update = e.first['created_at']
    event = Activity.new(
              posted_by: user,
              project_id: project_id,
              category: CATEGORY[:Basecamp2],
              title: e.first['target'],
              note: '',
              is_public: true,
              backend_id: e.first['eventable']['id'],
              last_sent_date: update.to_datetime,
              last_sent_date_epoch: update.to_datetime.to_i,
              email_messages: e.to_json
        )

    if event.valid?
      event.save
    end
  end

  # Note: copy_email_activities() is executed during the onboarding process (from User.confirm_projects_for_user), so SFDC activity is not pushed back to Salesforce here because the user will not have provided SFDC log-in information yet (and we only log activity going forward).
  def self.copy_email_activities(source_project, target_project)
    return if source_project.activities.empty?

    val = []

    source_project.activities.each do |c|
      if c.category == 'Conversation'
        val << "('#{c.posted_by}', '#{target_project.id}', '#{c.category}', #{Activity.sanitize(c.title)}, #{c.is_public}, '#{c.backend_id}', '#{c.last_sent_date}', '#{c.last_sent_date_epoch}',
                  #{Activity.sanitize(c.from.to_json)},
                  #{Activity.sanitize(c.to.to_json)},
                  #{Activity.sanitize(c.cc.to_json)},
                  #{Activity.sanitize(c.email_messages.to_json)},
                  '#{c.created_at}', '#{c.updated_at}')"
      end
    end

    insert = 'INSERT INTO "activities" ("posted_by", "project_id", "category", "title", "is_public", "backend_id", "last_sent_date", "last_sent_date_epoch", "from", "to", "cc", "email_messages", "created_at", "updated_at") VALUES'
    on_conflict = "ON CONFLICT (category, backend_id, project_id) DO UPDATE SET last_sent_date = EXCLUDED.last_sent_date, last_sent_date_epoch = EXCLUDED.last_sent_date_epoch, updated_at = EXCLUDED.updated_at, email_messages = EXCLUDED.email_messages"
    values = val.join(', ')

    Activity.transaction do
      # Insert activities into database
      Activity.connection.execute([insert,values,on_conflict].join(' '))
    end
  end

  def email_messages
    messages = JSON.parse(read_attribute(:email_messages).to_json).map { |hash| Hashie::Mash.new(hash) }
  end

  def from
    if read_attribute(:from).nil?
      from = []
    else
      from = JSON.parse(read_attribute(:from).to_json).map { |hash| Hashie::Mash.new(hash) }
    end
  end

  def to
    if read_attribute(:to).nil?
      to = []
    else
      to = JSON.parse(read_attribute(:to).to_json).map { |hash| Hashie::Mash.new(hash) }
    end
  end

  def cc
    if read_attribute(:cc).nil?
      cc = []
    else
      cc = JSON.parse(read_attribute(:cc).to_json).map { |hash| Hashie::Mash.new(hash) }
    end
  end

  def email_addresses
    carbon_copy = cc || []
    sent_to = to || []

    emails = Set.new
    from.each { |entry| emails.add(entry.address) }
    sent_to.each { |entry| emails.add(entry.address) }
    carbon_copy.each { |entry| emails.add(entry.address) }
    emails
  end

  def is_visible_to(user)
    project.is_visible_to(user) && ( is_public || email_addresses.include?(user.email) )
  end

  ### methods to batch change jsonb columns
  # convenience method to make input easier compared to time_shift
  def time_jump(date)
    time_shift((date - self.last_sent_date).round)
  end

  # updates all sent_date related fields for the activity by sec (time in seconds)
  def time_shift(sec)
    self.last_sent_date += sec
    self.last_sent_date_epoch = (self.last_sent_date_epoch.to_i + sec).to_s
    em = self.email_messages
    em.each do |e|
      e.sentDate += sec if self.category == CATEGORY[:Conversation]
      e.end_epoch += sec if self.category == CATEGORY[:Meeting]
    end
    self.email_messages = em
    self.attachments.each do |a|
      a.sent_date += sec
      a.save
    end
    self.save
  end

  # finds all instances of email1 and replaces all with email2 in from/to/cc and email_messages for the activity
  # email1 should be passed as a string, e.g. 'klu@contextsmith.com'
  # email 2 should be passed in the format <#Hashie::Mash address: a, personal: p>
  # the email2 hash can also be created at runtime if it is just passed as a string, then passing a personal is recommended
  def email_replace_all(email1, email2, personal=nil)
    email2 = Hashie::Mash.new({address: email2, personal: personal}) unless email2.respond_to?(:address) && email2.respond_to?(:personal)

    email_replace(self, email1, email2)

    if self.category == CATEGORY[:Conversation]
      em = self.email_messages
      unless em.blank?
        em.each_with_index { |e, j| em[j] = email_replace(e, email1, email2) }
        self.email_messages = em
      end
    end

    self.save
  end

  private
  # helper method for email_replace_all, used to replace the emails in from/to/cc
  def email_replace(message, email1, email2)
    from = message.from
    unless from.blank?
      from.each_with_index { |f, i| from[i] = email2 if f.address == email1 }
      message.from = from
    end

    to = message.to
    unless to.blank?
      to.each_with_index { |t, i| to[i] = email2 if t.address == email1 }
      message.to = to
    end

    cc = message.cc
    unless cc.blank?
      cc.each_with_index { |c, i| cc[i] = email2 if c.address == email1 }
      message.cc = cc
    end

    message
  end

   def self.rag_note(score)
    if score
      s = "Status set to "
      if score == 3
        s + Project::RAGSTATUS[:Green]
      elsif score == 2
        s + Project::RAGSTATUS[:Amber]
      elsif score == 1
        s + Project::RAGSTATUS[:Red]
      end
    end
  end

  # Copied from "app/helpers/application_helper.rb"
  def self.get_conversation_member_names(from, to, cc, trailing_text="other", size_limit=4)
    cc_size = (cc.nil? ? 0 : cc.size)
    to_size = (to.nil? ? 0 : to.size)
    from_size = (from.nil? ? 0 : from.size)

    total_size = from_size + to_size + cc_size

    if to_size <= size_limit and cc_size == 0
      return self.get_first_names(from, to, cc)
    elsif to_size <= size_limit and cc_size > 0
      remaining = size_limit - to_size
      if remaining == 0
        if trailing_text=="other"
          return self.get_first_names(from, to, nil) + " and " + pluralize(total_size - size_limit, 'other')
        else
          return "All"
        end
      else # ramaining > 0
        if cc_size > remaining
          if trailing_text=="other"
            return self.get_first_names(from, to, cc[0..(remaining-1)]) + " and " + pluralize(cc_size - remaining, 'other')
          else
            return "All"
          end
        else # cc_size <= remaining
          return self.get_first_names(from, to, cc)
        end
      end
    elsif to_size >= size_limit
      remaining = 0
      if trailing_text=="other"
        return self.get_first_names(from, to[0..size_limit], nil) + " and " + pluralize(total_size - size_limit, 'other')
      else
        return "All"
      end
    end
  end

  # Copied from "app/helpers/application_helper.rb"
  def self.get_first_names(from, to, cc)
    a = []

    if !from.empty?
      if from[0]["personal"].nil?
        a << from[0]["address"]
      else
        a << get_first_name(from[0]["personal"])
      end
    end

    unless to.nil? or to.empty?
      to.each do |n|
        if n["personal"].nil?
          a << n["address"]
        else
          a << get_first_name(n["personal"])
        end
      end
    end

    unless cc.nil? or cc.empty?
      cc.each do |n|
        if n["personal"].nil?
          a << n["address"]
        else
          a << get_first_name(n["personal"])
        end
      end
    end

    return a.join(', ')
  end

  # Copied from "app/helpers/projects_helper.rb"
  def self.smart_email_body(message, users_available)
    body = message.content.nil? || message.content.is_a?(String) ? message.content : message.content.body
    if users_available
      message.temporalItems.reverse_each do |i|
        task = i.taskAnnotation
        body.insert(task.endOffset, "</a>").insert(task.beginOffset, "<a class=\"suggested-action\" data-message=\"#{message.messageId}\" data-due-date=\"#{Time.zone.at(i.resolvedDates.first).strftime('%Y-%m-%d')}\">")
      end if message.temporalItems
      simple_format(body, {}, sanitize: false)
    else
      simple_format(body)
    end
  end

  # Copied from "app/helpers/application_helper.rb"
  def self.get_calendar_interval(event)
    start = event.last_sent_date
    end_t = Time.zone.at(event.email_messages.last.end_epoch)
    if start.to_date == end_t.to_date
      return start.strftime("%l:%M%P") + ' - ' + end_t.strftime("%l:%M%P")
    elsif start == start.midnight && end_t == end_t.midnight # if there is no time, date only
      return start.strftime("%b %e") + ' - ' + end_t.strftime("%b %e")
    else
      return start.strftime("%b %e,%l:%M%P") + ' - ' + end_t.strftime("%b %e,%l:%M%P")
    end
  end

  # Copied from "app/helpers/application_helper.rb"
  def self.get_calendar_member_names(to, trailing_text="other", size_limit=6)
    attendees_size = (to.nil? ? 0 : to.size)

    if attendees_size <= size_limit
      return get_first_names([], to, nil)
    else
      if trailing_text == "other"
        return get_first_names([], to[0..size_limit], nil) + " and " + pluralize(attendees_size - size_limit, 'other')
      else
        return "All"
      end
    end
  end

  def self.get_CS_export_prefix_SOQL_predicate_string
    soql_predicate = []
    CATEGORY.each do |k, v|
      v = "E-mail" if v == CATEGORY[:Conversation]
      soql_predicate << "Subject like '#{CS_ACTIVITY_SFDC_EXPORT_SUBJ_PREFIX} #{v}:%'"
    end
    soql_predicate.join(" OR ")
  end
end
