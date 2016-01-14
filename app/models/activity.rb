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
#  from                 :jsonb            default({}), not null
#  to                   :jsonb            default({}), not null
#  cc                   :jsonb            default({}), not null
#  email_messages       :jsonb            default({}), not null
#  project_id           :uuid             not null
#  posted_by            :uuid             not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#
# Indexes
#
#  index_activities_on_backend_id_and_project_id  (backend_id,project_id) UNIQUE
#  index_activities_on_email_messages             (email_messages)
#

class Activity < ActiveRecord::Base
	belongs_to :project

	CATEGORY = %w(Conversation Note Status)

	def self.load(data, project, user)
		activities = []

		data_hash = JSON.parse(data.to_s).map { |hash| Hashie::Mash.new(hash) }

		Activity.transaction do
      data_hash.each do |d|
        d.conversations.each do |c|

          insert = 'INSERT INTO "activities" ("posted_by", "project_id", "category", "title", "is_public", "backend_id", "last_sent_date", "last_sent_date_epoch", "from", "to", "cc", "email_messages", "created_at", "updated_at") VALUES'
          values = "('#{user.id}', '#{project.id}', 'Conversations', '#{c.subject}', true, '#{c.id}', '#{Time.zone.at(c.lastSentDate)}', '#{c.lastSentDate}', 
                     #{Activity.sanitize(c.contextMessages[0].from.to_json)}, 
                     #{Activity.sanitize(c.contextMessages[0].to.to_json)}, 
                     #{Activity.sanitize(c.contextMessages[0].cc.to_json)}, 
                     #{Activity.sanitize(c.contextMessages.to_json)}, 
                     '#{Time.now}', '#{Time.now}')"
          on_conflict = "ON CONFLICT (backend_id, project_id) DO UPDATE SET email_messages = " + Activity.sanitize(c.contextMessages.to_json)
          
          # Insert activities into database
          Activity.connection.execute([insert,values,on_conflict].join(' '))

          # Create activities object
          activities << Activity.new(
                          posted_by: user.id,
                          project_id: project.id,
                          category: "Conversation",
                          title: c.subject,
                          note: '',
                          is_public: true,
                          backend_id: c.id,
                          last_sent_date: Time.zone.at(c.lastSentDate),
                          last_sent_date_epoch: c.lastSentDate,
                          from: c.contextMessages[0].from, # take from first message
                          to: c.contextMessages[0].to,     # take from first message
                          cc: c.contextMessages[0].cc,     # take from first message
                          email_messages: c.contextMessages
                          )
        end
      end
    end

    return activities
	end

	def email_messages
		messages = JSON.parse(read_attribute(:email_messages).to_json).map { |hash| Hashie::Mash.new(hash) }
	end

	def from
		from = JSON.parse(read_attribute(:from).to_json).map { |hash| Hashie::Mash.new(hash) }
	end

	def to
		to = JSON.parse(read_attribute(:to).to_json).map { |hash| Hashie::Mash.new(hash) }
	end

	def cc
		cc = JSON.parse(read_attribute(:cc).to_json).map { |hash| Hashie::Mash.new(hash) }
	end
end
