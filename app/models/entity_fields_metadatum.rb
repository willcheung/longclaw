# == Schema Information
#
# Table name: entity_fields_metadata
#
#  id                     :integer          not null, primary key
#  organization_id        :uuid             not null
#  entity_type            :string           not null
#  name                   :string           not null
#  default_value          :string
#  salesforce_field       :string
#  read_permission_role   :string           not null
#  update_permission_role :string           not null
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#
# Indexes
#
#  entity_fields_metadata_idx  (organization_id,entity_type)
#

class EntityFieldsMetadatum < ActiveRecord::Base
  before_save :no_salesforce_field

  belongs_to :organization

  validates :entity_type, presence: true
  validates :name, presence: true, length: { maximum: 30 }
  validates :read_permission_role, presence: true    # Currently unused
  validates :update_permission_role, presence: true  # Currently unused

  ENTITY_TYPE = { Account: 'Account', Stream: 'Stream', Contact: 'Contact' }

  # Create default entity fields metadata info for a new organization
  def self.create_default_for(organization)
    organization.entity_fields_metadatum.delete_all  #clear all old meta fields
    EntityFieldsMetadatum::ENTITY_TYPE.values.each do |etype|
      meta = Account::FIELDS_META if etype == EntityFieldsMetadatum::ENTITY_TYPE[:Account]
      meta = Project::FIELDS_META if etype == EntityFieldsMetadatum::ENTITY_TYPE[:Stream]
      meta = Contact::FIELDS_META if etype == EntityFieldsMetadatum::ENTITY_TYPE[:Contact]

      meta.each do |fname|
        organization.entity_fields_metadatum.create!(entity_type: etype, name: fname, read_permission_role: User::ROLE[:Observer], update_permission_role: User::ROLE[:Poweruser])
      end if meta.present?
    end 
  end

  def self.get_sfdc_fields_mapping_for(organization)
    self.all.where.not("salesforce_field is null").pluck(:name, :salesforce_field)
  end

  private

  # if user tries to save/update a field to '', make it "null" instead
  def no_salesforce_field
    self.salesforce_field = nil if !salesforce_field.nil? && salesforce_field.empty?
  end
end
