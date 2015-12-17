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
#  index_activities_on_email_messages  (email_messages)
#

class Activity < ActiveRecord::Base
	belongs_to :project

	CATEGORY = %w(Conversation Note Status)

	def manual_load_conversations
		file = File.open("/Users/willcheung/Downloads/contextsmith-json-3.txt", "r")
	  data = file.read
	  file.close

	  p = Project.find_by_name("Project Galatic Empire")
	  u = User.find_by_email("willycheung@gmail.com")

	  data = JSON.parse(data)
	  data.each do |d|
	  	d["conversations"].each do |c|
	  		Activity.create(
	  										posted_by: u.id,
	  										project_id: p.id,
	  										category: "Conversation",
	  										title: c["subject"],
	  										note: '',
	  										is_public: true,
	  										backend_id: c["id"],
	  										last_sent_date: Time.zone.at(c["lastSentDate"]),
	  										last_sent_date_epoch: c["lastSentDate"],
	  										from: c["contextMessages"][0]["from"], # take from first message
	  										to: c["contextMessages"][0]["to"],		 # take from first message
	  										cc: c["contextMessages"][0]["cc"],		 # take from first message
	  										email_messages: c["contextMessages"]
	  										)
	  	end
	  end
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
