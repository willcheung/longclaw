class CreateCustomFields < ActiveRecord::Migration
  def change
    create_table :custom_fields do |t|
      t.uuid    :organization_id, null:false
      t.belongs_to :custom_fields_metadata, null:false
      #t.uuid    :customizable, polymorphic: true, index : true
      t.string  :customizable_type, null:false
      t.uuid    :customizable_uuid, null:false  # FK
      t.string  :value      # character varying ("varchar")

      t.timestamps null: false
    end

    add_index :custom_fields, [:organization_id, :custom_fields_metadata_id, :customizable_uuid], name: 'custom_fields_idx'
  end
end
