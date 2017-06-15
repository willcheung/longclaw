class CreateEntityFieldsMetadata < ActiveRecord::Migration
  def change
    create_table :entity_fields_metadata do |t|
      t.uuid    :organization_id, null:false
      t.string  :entity_type, null:false              # EntityFieldsMetadatum::ENTITY_TYPE
      t.string  :name, null:false                     # Entity::FIELDS_META
      t.string  :default_value
      t.belongs_to :custom_lists_metadata
      t.string  :salesforce_field
      t.string  :read_permission_role, null:false     # User::ROLE
      t.string  :update_permission_role, null:false   # User::ROLE

      t.timestamps null: false
    end

    add_index :entity_fields_metadata, [:organization_id, :entity_type], name: 'entity_fields_metadata_idx'

    reversible do |dir|
      dir.up do
        Organization.all.each do |org|
          EntityFieldsMetadatum.create_default_for(org)
        end
      end
    end
  end
end

