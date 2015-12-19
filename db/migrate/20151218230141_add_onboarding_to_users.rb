class AddOnboardingToUsers < ActiveRecord::Migration
  def change
  	add_column :users, :onboarding_step, :integer
  	add_column :users, :cluster_create_date, :datetime
  	add_column :users, :cluster_update_date, :datetime
  end
end
