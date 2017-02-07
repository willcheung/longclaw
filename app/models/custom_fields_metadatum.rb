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
#  custom_fields_metadata_idx  (organization_id,entity_type) UNIQUE
#

class CustomFieldsMetadatum < ActiveRecord::Base
	after_create  :create_custom_fields

	belongs_to :organization
	has_many :custom_fields, class_name: "CustomField", foreign_key: "custom_fields_metadata_id", dependent: :destroy
	validates :name, presence: true

	ENTITY_TYPE = { Account: 'Account', Project: 'Stream', User: 'User (coming soon)' }
	DATA_TYPE = { Text: 'Text', Number: 'Number', List: 'List (coming soon)' }

	# Checks the passed type 'typeStr' to see if it is a valid ENTITY_TYPE's (use matchKey=false if you want to match the mapped value and not the key itself) and returns the *key* value, otherwise returns nil 
	# (e.g., passing validateAndReturnValidEntityType("Project") or validateAndReturnValidEntityType("Stream",false) will both return CustomFieldsMetadatum::ENTITY_TYPE[:Project])
	def self.validateAndReturnValidEntityType(typeStr, matchKey=true)
		return nil if typeStr == nil
		ENTITY_TYPE.each do |t|
			if matchKey
				return t[0].to_s if t[0].to_s == typeStr.to_s
			else
				return t[0].to_s if t[1].to_s == typeStr.to_s
			end
		end
		return nil
	end

	private

	# Create a new custom field for an existing accounts, or create all custom fields for a new account
	def create_custom_fields
		_accounts = self.organization.accounts
		if self.entity_type == "Account"
			_accounts.each { |a| CustomField.create(organization:self.organization, custom_fields_metadatum:self, customizable_uuid:a.id, customizable_type:"Account") }
		elsif self.entity_type == "Project"
			_accounts.each do |a|
				a.projects.each { |p| CustomField.create(organization:self.organization, custom_fields_metadatum:self, customizable_uuid:p.id, customizable_type:"Project") }
			end
		else
			print "Error! Unknown entity_type; cannot create new custom fields."
		end
	end
end
