class AddScoreToNotifications < ActiveRecord::Migration
  def change
  	add_column :notifications, :score, :real, :default => 0.0

  	Notification.all.each do |n|
  		if n.category==Notification::CATEGORY[:Alert]
  			query = <<-SQL
        SELECT messages->>'sentimentItems' as sentiment_item
        FROM activities, LATERAL jsonb_array_elements(email_messages) messages
        WHERE backend_id='#{n.conversation_id}' and messages ->>'messageId' = '#{n.message_id}' and project_id = '#{n.project_id}'
      	SQL

      	result= Activity.find_by_sql(query)

      	if result.length > 1
      		puts "alert!!!!!!!!!!!!"
      	end

		    if(!result.nil? and !result[0].nil? and !result[0].sentiment_item.nil?)
		      sentiment_item = JSON.parse(result[0].sentiment_item)

		      if !sentiment_item.nil?

		      	# ex: -0.9857075620311126 -> -0.9857
		      	score =  sentiment_item[0]['score'].to_s[0,7].to_f

		      	# threshold 0.95, delete anything that is smaller
		      	if score >=-0.95
		      		n.delete
		      	else
		      		n.score = score
		      		n.save
		      	end
		      end
		    end
  		end
  	end
  end
end
