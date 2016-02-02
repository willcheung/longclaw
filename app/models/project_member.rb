# == Schema Information
#
# Table name: project_members
#
#  id         :uuid             not null, primary key
#  project_id :uuid
#  contact_id :uuid
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  user_id    :uuid
#
# Indexes
#
#  index_project_members_on_contact_id  (contact_id)
#  index_project_members_on_project_id  (project_id)
#  index_project_members_on_user_id     (user_id)
#

class ProjectMember < ActiveRecord::Base
	belongs_to :project
	belongs_to :contact
	belongs_to :user

	validates :project_id, uniqueness: {:scope => [:contact_id, :user_id]}
end
