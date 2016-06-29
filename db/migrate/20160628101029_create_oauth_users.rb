class CreateOauthUsers < ActiveRecord::Migration
  def change
    create_table :oauth_users do |t|
      t.string :oauth_provider,     null: false
      t.string :oauth_provider_uid, null: false
      t.string :oauth_access_token, null: false
      t.string :oauth_refresh_token
      t.string :oauth_instance_url, null: false
      t.string :oauth_user_name,    null: false, default: ""
      t.uuid :organization_id,      null: false

      t.timestamps null: false
    end

    add_index :oauth_users,[:oauth_provider,:oauth_user_name, :oauth_instance_url], name: "oauth_per_user", unique: true

  end
end
