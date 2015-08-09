class CreateOrganizations < ActiveRecord::Migration
  def change
    create_table :organizations, id: :uuid do |t|
      t.string 	:name
      t.string 	:domain
      t.integer :owner_id
      t.boolean	:is_active, default: true

      t.timestamps null: false
    end
  end
end
