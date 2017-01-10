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

	validates :project_id, uniqueness: {:scope => [:user_id]}
end
