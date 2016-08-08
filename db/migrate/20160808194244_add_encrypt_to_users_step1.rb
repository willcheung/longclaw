class AddEncryptToUsersStep1 < ActiveRecord::Migration
  def change
  	add_column :users, :encrypted_oauth_refresh_token, :string, default: ""
  	add_column :users, :encrypted_oauth_refresh_token_iv, :string, default: ""

  	rename_column :users, :oauth_refresh_token, :plain_oauth_refresh_token
  end
end
