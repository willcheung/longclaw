class TimesheetEntries < ActiveRecord::Migration
  def change
  	create_table :timesheet_entries, id: :uuid do |t|
    	t.uuid	:timesheet_id
    	t.uuid	:task_id
    	t.string 	:notes
    	t.date		:date
    	t.decimal	:hours

      t.timestamps null: false
    end
  end
end
