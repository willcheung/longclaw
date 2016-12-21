class AddSubscriptionTypesToProjectSubscribers < ActiveRecord::Migration
  def change
    add_column :project_subscribers, :daily, :boolean, default: true, null: false
    add_column :project_subscribers, :weekly, :boolean, default: true, null: false
  end
end
