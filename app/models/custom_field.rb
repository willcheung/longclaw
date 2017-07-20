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
#  custom_fields_idx                                               (organization_id,custom_fields_metadata_id)
#  index_custom_fields_on_customizable_type_and_customizable_uuid  (customizable_type,customizable_uuid)
#

class CustomField < ActiveRecord::Base
	belongs_to :organization
	belongs_to :custom_fields_metadatum, foreign_key: "custom_fields_metadata_id"
	belongs_to :customizable, polymorphic: true, foreign_key: "customizable_uuid"

	validates :custom_fields_metadatum, presence: true

	default_scope -> { order :custom_fields_metadata_id }  # strong default ordering of custom fields; row can be created "out of order"
end
