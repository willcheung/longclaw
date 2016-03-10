class CreateEmailActivitiesView < ActiveRecord::Migration
  def up
  	execute <<-SQL
      CREATE VIEW email_activities_last_14d AS
        SELECT 
        	id, 
					backend_id, 
					last_sent_date, 
					project_id, 
					is_public,
					jsonb_array_elements(email_messages) ->> 'sentDate' as sent_date 
				FROM 
					activities,
					LATERAL jsonb_array_elements(email_messages) messages
				WHERE
					category = 'Conversation'
					AND
					(messages ->> 'sentDate')::integer 
						BETWEEN EXTRACT(EPOCH FROM CURRENT_DATE - INTERVAL '14 DAYS')::integer 
						AND EXTRACT(EPOCH FROM clock_timestamp())::integer 
				GROUP BY 1,2,3,4,5,6
    SQL
    change_column :projects, :category, :string, :default => "Implementation"
  end

  def down
  	execute "DROP VIEW email_activites_last_14d"
  end
end
