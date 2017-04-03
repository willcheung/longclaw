class AddUserToOAuthUsers < ActiveRecord::Migration
  def change
    add_column :oauth_users, :user_id, :uuid

    remove_index :oauth_users, name: "oauth_per_user"
    add_index    :oauth_users, [:oauth_provider,:oauth_user_name, :oauth_instance_url, :organization_id, :user_id], name: "oauth_per_user", unique: true
  end
end
