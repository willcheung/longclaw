class RecreateIndexCustomFields < ActiveRecord::Migration
  def change
    remove_index :custom_fields, :column => [:organization_id, :custom_fields_metadata_id, :customizable_uuid], name: 'custom_fields_idx'
    add_index :custom_fields, [:customizable_type, :customizable_uuid]
    add_index :custom_fields, [:organization_id, :custom_fields_metadata_id], name: 'custom_fields_idx'
  end
end
