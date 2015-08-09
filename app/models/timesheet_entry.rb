# == Schema Information
#
# Table name: timesheet_entries
#
#  id           :uuid             not null, primary key
#  timesheet_id :uuid
#  task_id      :uuid
#  notes        :string
#  date         :date
#  hours        :decimal(, )
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#

class TimesheetEntry < ActiveRecord::Base
	belongs_to :task
	belongs_to	:timesheet

end
