class AddUserToOAuthUsers < ActiveRecord::Migration
  def change
    add_column :oauth_users, :user_id, :uuid
  end
end
