class AddOnboardingToUsers < ActiveRecord::Migration
  def change
  	add_column :users, :onboarding_step, :integer
  	add_column :users, :cluster_create_date, :datetime
  	add_column :users, :cluster_update_date, :datetime
  	add_column :project_members, :user_id, :uuid
  	add_column :projects, :is_confirmed, :boolean
  	add_column :users, :title, :string
  end
end
