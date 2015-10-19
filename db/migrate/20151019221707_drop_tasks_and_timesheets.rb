class DropTasksAndTimesheets < ActiveRecord::Migration
  def change
  	drop_table	:tasks
  	drop_table	:timesheets
  	drop_table	:timesheet_entries
  end
end
