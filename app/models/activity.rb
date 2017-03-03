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

class Activity < ActiveRecord::Base
  include PgSearch

  belongs_to :user, class_name: "User", foreign_key: "posted_by"
  belongs_to :project
  belongs_to :oauth_user
  has_many :comments, dependent: :destroy
  has_many :notifications, dependent: :destroy
  has_many :intergrations

  scope :pinned, -> { where is_pinned: true }
  scope :last_active_on, -> { maximum "last_sent_date" }
  scope :conversations, -> { where category: CATEGORY[:Conversation] }
  scope :notes, -> { where category: CATEGORY[:Note] }
  scope :meetings, -> { where category: CATEGORY[:Meeting] }
  scope :from_yesterday, -> { where last_sent_date: Time.current.yesterday.midnight..Time.current.yesterday.end_of_day }
  scope :from_lastweek, -> { where last_sent_date: (Time.current.yesterday.midnight - 1.weeks)..Time.current.yesterday.end_of_day }
  scope :reverse_chronological, -> { order last_sent_date: :desc }
  scope :visible_to, -> (user_email) { where "is_public IS TRUE OR \"from\" || \"to\" || \"cc\" @> '[{\"address\":\"#{user_email}\"}]'::jsonb" }
  scope :latest_rag_score, -> { notes.where.not( rag_score: nil) }


  acts_as_commentable

  pg_search_scope :search_note,
                  :against => [:note, :title],
                  :using => {
                      :tsearch => {:dictionary => "english"}
                  }


  CATEGORY = { Conversation: 'Conversation', Note: 'Note', Meeting: 'Meeting', JIRA: 'JIRA Issue', Salesforce: 'Salesforce Activity', Zendesk: 'Zendesk Ticket', Alert: 'Alert', Basecamp2: 'Basecamp2'}


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
            backend_id: c.id,
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

  def self.load_calendar(data, project, save_in_db=true, user_id='00000000-0000-0000-0000-000000000000')
    events = []
    val = []

    data_hash = data.map { |hash| Hashie::Mash.new(hash) }

    data_hash.each do |d|
      d.conversations.each do |c|
        event = c.messages.first
        # store miscellaneous data in email_messages column
        messages_data = [{ created: event.createdTime, updated: event.updatedTime, end_epoch: event.endTime }]

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
            backend_id: c.id,
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


  def self.load_salesforce_activities(project, organization_id, sfdc_id, type="Account", limit=200)
    val = []

    client = SalesforceService.connect_salesforce(organization_id)
    if type == "Account"
      query_statement = "select Name, (select Id, ActivityDate, ActivityType, ActivitySubtype, Owner.Name, Owner.Email, Subject, Description, Status, LastModifiedDate from ActivityHistories limit #{limit}) from Account where Id='#{sfdc_id}'"
    elsif type == "Opportunity"
      query_statement = "select Name, (select Id, ActivityDate, ActivityType, ActivitySubtype, Owner.Name, Owner.Email, Subject, Description, Status, LastModifiedDate from ActivityHistories limit #{limit}) from Opportunity where Id='#{sfdc_id}'"
    end

    activities = SalesforceService.query_salesforce(client, query_statement)

    activities.first.each do |a|
      if a.first == "ActivityHistories"
        if !a.second.nil?
          a.second.each do |c|
            owner = { "address": c.Owner.Email, "personal": c.Owner.Name }
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
    on_conflict = 'ON CONFLICT (category, backend_id, project_id) DO UPDATE SET last_sent_date = EXCLUDED.last_sent_date, last_sent_date_epoch = EXCLUDED.last_sent_date_epoch, updated_at = EXCLUDED.updated_at, note = EXCLUDED.note, email_messages = EXCLUDED.email_messages'
    values = val.join(', ')

    if !val.empty?
      Activity.transaction do
        # Insert activities into database
        Activity.connection.execute([insert,values,on_conflict].join(' '))
      end
    end
  end

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
    carbon_copy =  cc || []
    sent_to = to || []

    emails = Set.new
    from.each { |entry| emails.add(entry.address) }
    sent_to.each { |entry| emails.add(entry.address) }
    carbon_copy.each { |entry| emails.add(entry.address) }
    emails
  end

  def is_visible_to(user)
    is_public || email_addresses.include?(user.email)
  end

  ### methods to batch change jsonb columns
  # updates all sent_date related fields for the activity by sec (time in seconds)
  def timejump(sec)
    self.last_sent_date += sec
    self.last_sent_date_epoch = (self.last_sent_date_epoch.to_i + sec).to_s
    em = self.email_messages
    em.each do |e|
      e.sentDate += sec if self.category == CATEGORY[:Conversation]
      e.end_epoch += sec if self.category == CATEGORY[:Meeting]
    end
    self.email_messages = em
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

end
