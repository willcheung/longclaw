# == Schema Information
#
# Table name: project_members
#
#  id         :uuid             not null, primary key
#  project_id :uuid
#  contact_id :uuid
#  created_at :datetime         not null
#  updated_at :datetime         not null
#

class ProjectMember < ActiveRecord::Base
	belongs_to :project
	belongs_to :contact
end
