class AddEncryptToUsersStep3 < ActiveRecord::Migration
  def change
  	remove_column :users, :plain_oauth_refresh_token
  end
end
