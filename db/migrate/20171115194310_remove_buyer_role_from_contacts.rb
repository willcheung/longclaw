class RemoveBuyerRoleFromContacts < ActiveRecord::Migration
  def change
    remove_column :contacts, :buyer_role, :string
    reversible do |dir|
      dir.up do
        EntityFieldsMetadatum.where(entity_type: EntityFieldsMetadatum::ENTITY_TYPE[:Contact], name: "buyer_role").destroy_all
      end
      dir.down do
        Organization.all.each do |org|
          org.entity_fields_metadatum.create!(entity_type: EntityFieldsMetadatum::ENTITY_TYPE[:Contact], name: "buyer_role", salesforce_field: nil, read_permission_role: User::ROLE[:Observer], update_permission_role: User::ROLE[:Poweruser])
        end
      end
    end
  end
end
