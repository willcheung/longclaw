class CreateProfiles < ActiveRecord::Migration
  def change
    create_table :profiles do |t|
      t.text :emails, array: true, default: []
      t.datetime :expires_at
      t.jsonb :data

      t.timestamps null: false
    end
  end
end
