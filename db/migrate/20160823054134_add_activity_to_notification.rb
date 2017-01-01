class AddActivityToNotification < ActiveRecord::Migration
  def change
  	add_column :notifications, :activity_id, :integer, :default => -1

  	Notification.all.each do |n|
  		case n.category
  		when Notification::CATEGORY[:Alert], Notification::CATEGORY[:Action], Notification::CATEGORY[:Opportunity]
  			a = Activity.find_by(category: "Conversation", backend_id: n.conversation_id, project_id: n.project_id)
  			if !a.nil?
  				n.activity_id = a.id
  				n.save
  			else
  				puts "=========No Activity Found=========!!!"
  				puts n.id
  				puts "======================================"
  				n.delete
  			end
  		when Notification::CATEGORY[:Todo]
  			# no activity id
  		when Notification::CATEGORY[:Notification]
  			# not sure what this is, never seen one before

  		else
  			puts "Found weird category!!"
  			n.delete
  		end
  	end
  end
end
