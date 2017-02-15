class CreateCustomLists < ActiveRecord::Migration
  def change
    create_table :custom_lists do |t|
      t.belongs_to :custom_lists_metadata, null:false
      t.string    :option_value, null:false

      t.timestamps null: false
    end

    add_index :custom_lists, [:custom_lists_metadata_id]
  end
end
