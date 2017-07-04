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

  # Create default mappable entity fields metadata info for a new organization
  def self.create_default_for(organization)
    return if organization.nil?

    organization.entity_fields_metadatum.destroy_all  #discard all old meta fields
    ENTITY_TYPE.values.each do |etype|
      case etype
      when ENTITY_TYPE[:Account]
        meta = Account::MAPPABLE_FIELDS_META
      when ENTITY_TYPE[:Stream]
        meta = Project::MAPPABLE_FIELDS_META
      when ENTITY_TYPE[:Contact]
        meta = Contact::MAPPABLE_FIELDS_META
      else
        meta = []  #error; no-op
      end

      meta.keys.each do |name|
        organization.entity_fields_metadatum.create!(entity_type: etype, name: name, read_permission_role: User::ROLE[:Observer], update_permission_role: User::ROLE[:Poweruser])
      end if meta.present?
    end

    # Create a default mapping of "standard" SFDC fields to CS fields, 

    # Create lists of valid SFDC entity fields for reference, in case an expected "standard" SFDC field does not exist
    # We don't save SFDC custom fields (i.e., in our backend), so we query SFDC every time! :(
    sfdc_fields = SalesforceController.get_salesforce_fields(organization_id: organization.id)
    if sfdc_fields.present?
      sfdc_account_fields = sfdc_fields[:sfdc_account_fields].map{|f| f[0]}
      sfdc_opportunity_fields = sfdc_fields[:sfdc_opportunity_fields].map{|f| f[0]}
      sfdc_contact_fields = sfdc_fields[:sfdc_contact_fields].map{|f| f[0]}

      # Map the CS Account field to the SFDC Account field. The following lines may need to change if Account::MAPPABLE_FIELDS_META changes
      #organization.entity_fields_metadatum.find_by(entity_type: ENTITY_TYPE[:Account], name: "name").update(salesforce_field: "Name") if sfdc_account_fields.include? "Name"
      organization.entity_fields_metadatum.find_by(entity_type: ENTITY_TYPE[:Account], name: "address").update(salesforce_field: "BillingAddress") if sfdc_account_fields.include? "BillingAddress"
      organization.entity_fields_metadatum.find_by(entity_type: ENTITY_TYPE[:Account], name: "description").update(salesforce_field: "Description") if sfdc_account_fields.include? "Description"
      organization.entity_fields_metadatum.find_by(entity_type: ENTITY_TYPE[:Account], name: "phone").update(salesforce_field: "Phone") if sfdc_account_fields.include? "Phone"
      organization.entity_fields_metadatum.find_by(entity_type: ENTITY_TYPE[:Account], name: "revenue_potential").update(salesforce_field: "AnnualRevenue") if sfdc_account_fields.include? "AnnualRevenue"
      organization.entity_fields_metadatum.find_by(entity_type: ENTITY_TYPE[:Account], name: "website").update(salesforce_field: "Website") if sfdc_account_fields.include? "Website"

      # Map the CS Stream field to the SFDC Opportunity field. The following lines may need to change if Project::MAPPABLE_FIELDS_META changes
      #organization.entity_fields_metadatum.find_by(entity_type: ENTITY_TYPE[:Stream], name: "name").update(salesforce_field: "Name") if sfdc_opportunity_fields.include? "Name"
      organization.entity_fields_metadatum.find_by(entity_type: ENTITY_TYPE[:Stream], name: "amount").update(salesforce_field: "Amount") if sfdc_opportunity_fields.include? "Amount"
      organization.entity_fields_metadatum.find_by(entity_type: ENTITY_TYPE[:Stream], name: "close_date").update(salesforce_field: "CloseDate") if sfdc_opportunity_fields.include? "CloseDate"
      organization.entity_fields_metadatum.find_by(entity_type: ENTITY_TYPE[:Stream], name: "description").update(salesforce_field: "Description") if sfdc_opportunity_fields.include? "Description"
      organization.entity_fields_metadatum.find_by(entity_type: ENTITY_TYPE[:Stream], name: "expected_revenue").update(salesforce_field: "ExpectedRevenue") if sfdc_opportunity_fields.include? "ExpectedRevenue"
      organization.entity_fields_metadatum.find_by(entity_type: ENTITY_TYPE[:Stream], name: "stage").update(salesforce_field: "StageName") if sfdc_opportunity_fields.include? "StageName"

      # Map the CS Contact field to the SFDC Contact field. The following lines may need to change if Contact::MAPPABLE_FIELDS_META changes
      #organization.entity_fields_metadatum.find_by(entity_type: ENTITY_TYPE[:Contact], name: "source").update(salesforce_field: "LeadSource") if sfdc_contact_fields.include? "LeadSource"
      #organization.entity_fields_metadatum.find_by(entity_type: ENTITY_TYPE[:Contact], name: "mobile").update(salesforce_field: "MobilePhone") if sfdc_contact_fields.include? "MobilePhone"
      organization.entity_fields_metadatum.find_by(entity_type: ENTITY_TYPE[:Contact], name: "background_info").update(salesforce_field: "Description") if sfdc_contact_fields.include? "Description"
      organization.entity_fields_metadatum.find_by(entity_type: ENTITY_TYPE[:Contact], name: "department").update(salesforce_field: "Department") if sfdc_contact_fields.include? "Department"
      organization.entity_fields_metadatum.find_by(entity_type: ENTITY_TYPE[:Contact], name: "email").update(salesforce_field: "Email") if sfdc_contact_fields.include? "Email"
      organization.entity_fields_metadatum.find_by(entity_type: ENTITY_TYPE[:Contact], name: "first_name").update(salesforce_field: "FirstName") if sfdc_contact_fields.include? "FirstName"
      organization.entity_fields_metadatum.find_by(entity_type: ENTITY_TYPE[:Contact], name: "last_name").update(salesforce_field: "LastName") if sfdc_contact_fields.include? "LastName"
      organization.entity_fields_metadatum.find_by(entity_type: ENTITY_TYPE[:Contact], name: "phone").update(salesforce_field: "Phone") if sfdc_contact_fields.include? "Phone"
      organization.entity_fields_metadatum.find_by(entity_type: ENTITY_TYPE[:Contact], name: "title").update(salesforce_field: "Title") if sfdc_contact_fields.include? "Title"
    end
  end

  # Returns a list of [mapped SFDC entity field name, CS entity field name] pairs, for a particular entity type (i.e., Account, Stream, or Contact).
  # Parameters:   organization_id - the Id of the organization
  #               entity_type - EntityFieldsMetadatum::ENTITY_TYPE 
  def self.get_sfdc_fields_mapping_for(organization_id:, entity_type:)
    self.where(organization_id: organization_id, entity_type: entity_type).where.not(salesforce_field: nil).pluck(:salesforce_field, :name)
  end

  private

  # if user tries to save/update a field to '', make it "null" instead
  def no_salesforce_field
    self.salesforce_field = nil if !salesforce_field.nil? && salesforce_field.empty?
  end
end
