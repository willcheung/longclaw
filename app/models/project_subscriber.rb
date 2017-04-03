# == Schema Information
#
# Table name: project_subscribers
#
#  id         :integer          not null, primary key
#  project_id :uuid
#  user_id    :uuid
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  daily      :boolean          default(TRUE), not null
#  weekly     :boolean          default(TRUE), not null
#
# Indexes
#
#  index_project_subscribers_on_email       (user_id)
#  index_project_subscribers_on_project_id  (project_id)
#

class ProjectSubscriber < ActiveRecord::Base
	belongs_to :project
	belongs_to :user

  scope :daily, -> { where daily: true }
  scope :weekly, -> { where weekly: true }

  scope :active_daily, -> { joins(:project).where(daily: true, projects: {is_confirmed: true, status: 'Active'}) }
  scope :active_weekly, -> { joins(:project).where(weekly: true, projects: {is_confirmed: true, status: 'Active'}) }

  validates :project_id, uniqueness: {:scope => [:user_id]}
end
