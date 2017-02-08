class CreateCustomFieldsMetadata < ActiveRecord::Migration
  def change
    create_table :custom_fields_metadata do |t|
      t.uuid    :organization_id, null:false
      t.string  :entity_type, null:false
      t.string  :name, null:false
      t.string  :data_type, null:false                # CustomFieldsMetadatum::DATA_TYPE
      t.string  :update_permission_level, null:false  # User::ROLE

      t.timestamps null: false
    end

    add_index :custom_fields_metadata, [:organization_id, :entity_type], name: 'custom_fields_metadata_idx'
  end
end
