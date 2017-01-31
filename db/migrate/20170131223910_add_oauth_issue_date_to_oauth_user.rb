class AddOauthIssueDateToOauthUser < ActiveRecord::Migration
  def change
    add_column :oauth_users, :oauth_issue_date, :datetime
  end
end
