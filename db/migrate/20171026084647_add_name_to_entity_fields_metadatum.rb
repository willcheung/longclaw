class AddNameToEntityFieldsMetadatum < ActiveRecord::Migration
  def change
    reversible do |dir|
      dir.up do
        Organization.all.each do |org|
            org.entity_fields_metadatum.create!(entity_type: EntityFieldsMetadatum::ENTITY_TYPE[:Account], name: "name", salesforce_field: "Name", read_permission_role: User::ROLE[:Observer], update_permission_role: User::ROLE[:Poweruser])
            org.entity_fields_metadatum.create!(entity_type: EntityFieldsMetadatum::ENTITY_TYPE[:Project], name: "name", salesforce_field: "Name", read_permission_role: User::ROLE[:Observer], update_permission_role: User::ROLE[:Poweruser])
        end
      end
      dir.down do
        # Don't undo any mapping
      end
    end
  end
end
