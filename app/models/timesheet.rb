# == Schema Information
#
# Table name: timesheets
#
#  id            :uuid             not null, primary key
#  user_id       :uuid
#  calendar_week :integer
#  year          :string
#  status        :string
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#

class Timesheet < ActiveRecord::Base
	belongs_to :user
	has_many :timesheet_entries
	has_many :tasks, through: "timesheet_entries"

	STATUS = { draft: "Draft", submitted: "Submitted", approved: "Approved" }
end
