# == Schema Information
#
# Table name: entity_fields_metadata
#
#  id                       :integer          not null, primary key
#  organization_id          :uuid             not null
#  entity_type              :string           not null
#  name                     :string           not null
#  default_value            :string
#  custom_lists_metadata_id :integer
#  salesforce_field         :string
#  read_permission_role     :string           not null
#  update_permission_role   :string           not null
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#
# Indexes
#
#  entity_fields_metadata_idx  (organization_id,entity_type)
#

class EntityFieldsMetadatum < ActiveRecord::Base
  belongs_to :organization
  belongs_to :custom_lists_metadatum, foreign_key: "custom_lists_metadata_id"
  # To do: use 'default' value column

  validates :entity_type, presence: true
  validates :name, presence: true, length: { maximum: 30 }
  validates :read_permission_role, presence: true
  validates :update_permission_role, presence: true

  ENTITY_TYPE = { Account: 'Account', Stream: 'Stream', Contact: 'Contact' }

  # Create default entity fields metadata info for a new organization
  def self.create_default_for(organization)
    organization.entity_fields_metadatum.delete_all  #clear all old meta fields
    EntityFieldsMetadatum::ENTITY_TYPE.values.each do |etype|
      meta = Account::FIELDS_META if etype == EntityFieldsMetadatum::ENTITY_TYPE[:Account]
      meta = Project::FIELDS_META if etype == EntityFieldsMetadatum::ENTITY_TYPE[:Stream]
      meta = Contact::FIELDS_META if etype == EntityFieldsMetadatum::ENTITY_TYPE[:Contact]

      meta.each do |fname|
        organization.entity_fields_metadatum.create!(entity_type: etype, name: fname, read_permission_role: User::ROLE[:Poweruser], update_permission_role: User::ROLE[:Poweruser])
      end if meta.present?
    end 
  end
end
