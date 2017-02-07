# == Schema Information
#
# Table name: custom_fields
#
#  id                        :integer          not null, primary key
#  organization_id           :uuid             not null
#  custom_fields_metadata_id :integer          not null
#  customizable_type         :string           not null
#  customizable_uuid         :uuid             not null
#  value                     :string
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#
# Indexes
#
#  custom_fields_idx  (organization_id,custom_fields_metadata_id,customizable_uuid) UNIQUE
#

class CustomField < ActiveRecord::Base
	belongs_to :organization
	belongs_to :custom_fields_metadatum, foreign_key: "custom_fields_metadata_id"
	belongs_to :account, foreign_key: "customizable_uuid"
	belongs_to :project, foreign_key: "customizable_uuid"
	#belongs_to :user,    foreign_key: "customizable_uuid"
 
	# Returns associated entity to this custom field; mimics polymorphic behavior "belongs_to :customizable, :polymorphic => true"
	def customizable
		if self.customizable_type == "Account"
			return Account.joins(:custom_fields).where("custom_fields.id = ? and custom_fields.customizable_type = 'Account' and accounts.id = ?", self.id, self.customizable_uuid)
		elsif self.customizable_type == "Project" 
			return Project.joins(:custom_fields).where("custom_fields.id = ? and custom_fields.customizable_type = 'Project' and projects.id = ?", self.id, self.customizable_uuid)
		end
	end
end
