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

class ProjectMember < ActiveRecord::Base
	belongs_to :project
	belongs_to :contact
	belongs_to :user
end
