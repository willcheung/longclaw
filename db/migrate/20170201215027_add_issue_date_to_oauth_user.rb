class AddIssueDateToOauthUser < ActiveRecord::Migration
  def change
    add_column :oauth_users, :oauth_issued_date, :datetime
  end
end
