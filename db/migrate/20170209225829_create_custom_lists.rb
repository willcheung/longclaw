class CreateCustomLists < ActiveRecord::Migration
  def change
    create_table :custom_lists do |t|
      t.belongs_to :custom_lists_metadata, null:false
      t.string    :option_value, null:false

      t.timestamps null: false
    end

    add_index :custom_lists, [:custom_lists_metadata_id]

    # Create default system Custom Lists for all existing organizations
    reversible do |dir|
      dir.up do
        Organization.all.each do |org|
          CustomListsMetadatum.create_default_for(org)
        end
      end
      dir.down do
        CustomListsMetadatum.delete_all
      end
    end
  end
end
