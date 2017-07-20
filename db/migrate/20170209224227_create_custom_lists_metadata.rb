class CreateCustomListsMetadata < ActiveRecord::Migration
  def change
    create_table :custom_lists_metadata do |t|
      t.uuid      :organization_id, null: false
      t.string    :name, null: false
      t.boolean   :cs_app_list, null: false, default: false  # special system custom list: user may not rename or delete this list, and is not allowed to remove all options available to it
      
      t.timestamps null: false
    end

    add_index :custom_lists_metadata, [:organization_id, :name]

    # Add reference in custom_fields_metadata => custom_lists_metadata
    add_reference :custom_fields_metadata, :custom_lists_metadata, index: true
  end
end
