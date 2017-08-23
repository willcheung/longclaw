class AddProbabilityAndForecastToProjects < ActiveRecord::Migration
  def change
    add_column :projects, :probability, :decimal, precision: 5, scale: 2 # :smallint
    add_column :projects, :forecast, :string
    add_column :salesforce_opportunities, :forecast_category_name, :string
    add_column :salesforce_opportunities, :owner_id, :string
    
    reversible do |dir|
      dir.up do
        Organization.all.each do |org|
          org.entity_fields_metadatum.create!(entity_type: EntityFieldsMetadatum::ENTITY_TYPE[:Project], name: "probability", read_permission_role: User::ROLE[:Observer], update_permission_role: User::ROLE[:Poweruser])
          org.entity_fields_metadatum.create!(entity_type: EntityFieldsMetadatum::ENTITY_TYPE[:Project], name: "forecast", read_permission_role: User::ROLE[:Observer], update_permission_role: User::ROLE[:Poweruser])
          
          # Map to SFDC fields if exists for this org
          sfdc_fields = SalesforceController.get_salesforce_fields(organization_id: org.id)
          if sfdc_fields.present?  # if org has connected to SFDC
            sfdc_opportunity_fields = sfdc_fields[:sfdc_opportunity_fields].map{|f| f[0]}
            org.entity_fields_metadatum.find_by(entity_type: EntityFieldsMetadatum::ENTITY_TYPE[:Project], name: "probability").update(salesforce_field: "Probability") if sfdc_opportunity_fields.include? "Probability"
            org.entity_fields_metadatum.find_by(entity_type: EntityFieldsMetadatum::ENTITY_TYPE[:Project], name: "forecast").update(salesforce_field: "ForecastCategoryName") if sfdc_opportunity_fields.include? "ForecastCategoryName"  # ForecastCategory ?
          end
        end
      end
      dir.down do
        EntityFieldsMetadatum.where(name: "probability").destroy_all
        EntityFieldsMetadatum.where(name: "forecast").destroy_all
      end
    end
  end
end
