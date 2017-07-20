class AddOauthUserIdToIntegration < ActiveRecord::Migration
  def change
    add_reference :integrations, :oauth_user, index: true, foreign_key: true
  end
end
