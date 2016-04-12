class ModifyUserActivitiesViewHandleNull < ActiveRecord::Migration
    def up
	    execute <<-SQL
				DROP VIEW user_activities_last_14d;
				DROP VIEW email_activities_last_14d;

				CREATE OR REPLACE VIEW email_activities_last_14d AS
        SELECT 
        	id, 
					backend_id, 
					last_sent_date, 
					project_id, 
					is_public,
					jsonb_array_elements(email_messages) ->> 'messageId'::text as message_id,
					jsonb_array_elements(email_messages) ->> 'sentDate' as sent_date,
					jsonb_array_elements(email_messages) -> 'from' as from, 
					jsonb_array_elements(email_messages) -> 'to' as to,
					jsonb_array_elements(email_messages) -> 'cc' as cc
				FROM 
					activities,
					LATERAL jsonb_array_elements(email_messages) messages
				WHERE
					category = 'Conversation'
					AND
					(messages ->> 'sentDate')::integer 
						BETWEEN EXTRACT(EPOCH FROM CURRENT_DATE - INTERVAL '14 DAYS')::integer 
						AND EXTRACT(EPOCH FROM clock_timestamp())::integer 
				GROUP BY 1,2,3,4,5,6,7,8,9,10;
				
				CREATE OR REPLACE VIEW user_activities_last_14d AS
					SELECT 
						backend_id, 
						message_id,
						project_id, 
						last_sent_date, 
						jsonb_array_elements("from") ->> 'address' as from,
						case 
							when "to" = 'null' then NULL
							else jsonb_array_elements("to") ->> 'address'
						end AS to,
						case 
							when "cc" = 'null' then NULL
							else jsonb_array_elements("cc") ->> 'address'
						end AS cc
					FROM email_activities_last_14d 
					GROUP BY 1,2,3,4,5,6,7;
	    SQL
	  end

   def down
    execute <<-SQL
    	DROP VIEW user_activities_last_14d;
    	DROP VIEW email_activities_last_14d;

			CREATE OR REPLACE VIEW email_activities_last_14d AS
        SELECT 
        	id, 
					backend_id, 
					last_sent_date, 
					project_id, 
					is_public,
					jsonb_array_elements(email_messages) ->> 'sentDate' as sent_date,
					jsonb_array_elements(email_messages) -> 'from' as from, 
					jsonb_array_elements(email_messages) -> 'to' as to,
					jsonb_array_elements(email_messages) -> 'cc' as cc
				FROM 
					activities,
					LATERAL jsonb_array_elements(email_messages) messages
				WHERE
					category = 'Conversation'
					AND
					(messages ->> 'sentDate')::integer 
						BETWEEN EXTRACT(EPOCH FROM CURRENT_DATE - INTERVAL '14 DAYS')::integer 
						AND EXTRACT(EPOCH FROM clock_timestamp())::integer 
				GROUP BY 1,2,3,4,5,6,7,8,9;

			CREATE OR REPLACE VIEW user_activities_last_14d AS
				SELECT 
					backend_id, 
					project_id, 
					last_sent_date, 
					jsonb_array_elements("from") ->> 'address' as from,
					jsonb_array_elements("to") ->> 'address' as to,
					jsonb_array_elements("cc") ->> 'address' as cc
				FROM email_activities_last_14d 
				GROUP BY 1,2,3,4,5,6;
    SQL
  end
end
