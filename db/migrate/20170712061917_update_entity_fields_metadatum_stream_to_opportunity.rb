class UpdateEntityFieldsMetadatumStreamToOpportunity < ActiveRecord::Migration
  def change
    reversible do |dir|
      dir.up do
        Organization.all.each do |org|
          org.entity_fields_metadatum.where(entity_type: 'Stream').update_all(entity_type: EntityFieldsMetadatum::ENTITY_TYPE[:Project])
          org.custom_lists_metadatum.where(name: 'Stream Type').update_all(name: 'Opportunity Type')
        end
      end
      dir.down do
        Organization.all.each do |org|
          org.entity_fields_metadatum.where(entity_type: EntityFieldsMetadatum::ENTITY_TYPE[:Project]).update_all(entity_type: 'Stream')
          org.custom_lists_metadatum.where(name: 'Opportunity Type').update_all(name: 'Stream Type')
        end
      end
    end
  end
end
