class CreateCompanyProfiles < ActiveRecord::Migration
  def change
    create_table :company_profiles do |t|
      t.string :domain, default: '', null: false
      t.datetime :expires_at
      t.jsonb :data

      t.timestamps null: false

      t.index :domain
    end
  end
end
