class AddMobilePhoneToEntityFieldsMetadatum < ActiveRecord::Migration
  def change
    reversible do |dir|
      dir.up do
        Organization.all.each do |org|
          org.entity_fields_metadatum.create!(entity_type: EntityFieldsMetadatum::ENTITY_TYPE[:Contact], name: "mobile", read_permission_role: User::ROLE[:Observer], update_permission_role: User::ROLE[:Poweruser])
          
          # Map to SFDC fields if exists for this org
          sfdc_fields = SalesforceController.get_salesforce_fields(organization_id: org.id)
          if sfdc_fields.present?  # if org has connected to SFDC
            sfdc_contact_fields = sfdc_fields[:sfdc_contact_fields].map{|f| f[0]}
            org.entity_fields_metadatum.find_by(entity_type: EntityFieldsMetadatum::ENTITY_TYPE[:Contact], name: "mobile").update(salesforce_field: "MobilePhone") if sfdc_contact_fields.include? "MobilePhone"
          end
        end
      end
      dir.down do
        EntityFieldsMetadatum.where(entity_type: EntityFieldsMetadatum::ENTITY_TYPE[:Contact], name: "mobile").destroy_all
      end
    end
  end
end