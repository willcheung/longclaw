class ModifyUserActivitiesViewHandleNull < ActiveRecord::Migration
    def up
	    execute <<-SQL
				CREATE OR REPLACE VIEW user_activities_last_14d AS
					SELECT 
						backend_id, 
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
					GROUP BY 1,2,3,4,5,6
	    SQL
	  end

   def down
    execute <<-SQL
			CREATE OR REPLACE VIEW user_activities_last_14d AS
				SELECT 
					backend_id, 
					project_id, 
					last_sent_date, 
					jsonb_array_elements("from") ->> 'address' as from,
					jsonb_array_elements("to") ->> 'address' as to,
					jsonb_array_elements("cc") ->> 'address' as cc
				FROM email_activities_last_14d 
				GROUP BY 1,2,3,4,5,6
    SQL
  end
end
