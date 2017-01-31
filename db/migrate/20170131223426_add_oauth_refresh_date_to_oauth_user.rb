class AddOauthRefreshDateToOauthUser < ActiveRecord::Migration
  def change
    add_column :oauth_users, :oauth_refresh_date, :integer
  end
end
