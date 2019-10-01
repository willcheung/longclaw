class AddEmailSettingsToUsers < ActiveRecord::Migration
  def change
  	add_column :users, :email_weekly_tracking, :boolean, default: true
  	add_column :users, :email_onboarding_campaign, :boolean, default: true
  	add_column :users, :email_new_features, :boolean, default: true
  end
end
