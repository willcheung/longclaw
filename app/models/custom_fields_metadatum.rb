# == Schema Information
#
# Table name: custom_fields_metadata
#
#  id                      :integer          not null, primary key
#  organization_id         :uuid             not null
#  entity_type             :string           not null
#  name                    :string           not null
#  data_type               :string           not null
#  update_permission_level :string           not null
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#
# Indexes
#
#  custom_fields_metadata_idx  (organization_id,entity_type)
#

class CustomFieldsMetadatum < ActiveRecord::Base
	after_create  :create_custom_fields

	belongs_to :organization
	has_many :custom_fields, class_name: "CustomField", foreign_key: "custom_fields_metadata_id", dependent: :destroy
	validates :name, presence: true

	ENTITY_TYPE = { Account: 'Account', Project: 'Stream', User: 'User (coming soon)' }
	DATA_TYPE = { Text: 'Text', Number: 'Number', List: 'List (coming soon)' }

	# Checks the string 'type' to see if it is a valid ENTITY_TYPE.  If 'type' is valid, returns the ENTITY_TYPE (key); otherwise, returns nil. Use match_external_value=true to validate 'type' with the mapped value (the external value the user sees) instead of the key.
	# e.g., Calling validate_and_return_entity_type("Project") or validate_and_return_entity_type("Stream",true) will both return CustomFieldsMetadatum::ENTITY_TYPE[:Project]
	def self.validate_and_return_entity_type(type, match_external_value=false)
		return nil if type == nil
		ENTITY_TYPE.each do |t|
			if match_external_value
				return t[0].to_s if type.to_s == t[1].to_s
			else
				return t[0].to_s if type.to_s == t[0].to_s
			end
		end
		return nil
	end

	private

	# Create a new custom field for all existing entities of the appropriate entity type
	def create_custom_fields
		accounts = self.organization.accounts
		if self.entity_type == "Account"
			accounts.each { |a| CustomField.create(organization:self.organization, custom_fields_metadatum:self, customizable:a) }
		elsif self.entity_type == "Project"
			accounts.each do |a|
				a.projects.each { |p| CustomField.create(organization:self.organization, custom_fields_metadatum:self, customizable:p) }
			end
		else
			print "Error! Unknown entity_type; cannot create new custom fields."
		end
	end
end
