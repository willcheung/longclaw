class ActivitiesController < ApplicationController
  def load
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
	  										from: c["contextMessages"][0]["from"],
	  										to: c["contextMessages"][0]["to"],
	  										cc: c["contextMessages"][0]["cc"],
	  										email_messages: c["contextMessages"]
	  										)
	  	end
	  end

	  render text: data
  end
end