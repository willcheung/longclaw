# == Schema Information
#
# Table name: tasks
#
#  id              :uuid             not null, primary key
#  project_id      :uuid
#  name            :string           default(""), not null
#  description     :text
#  assignee_id     :integer
#  status          :string
#  is_billable     :boolean          default(TRUE)
#  hourly_rate     :integer
#  external_url    :string
#  estimated_hours :integer
#  external_id     :integer
#  external_source :text
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#

class Task < ActiveRecord::Base
	belongs_to :project
	belongs_to :user, foreign_key: "assignee_id"
	has_many :timesheet_entries
	has_many :timesheets, through: "timesheet_entries"

	STATUS = %w(Active Completed Later)

	def self.find_total_hours_per_task(tasks)
		task_ids = tasks.ids.map { |s| "'#{s}'" }.join(',')
		return self.find_by_sql("select t.id, sum(hours) as total_hours
														from timesheet_entries te
															join tasks t on t.id = te.task_id
														where task_id in (#{task_ids})
														group by t.id")
	end
end
