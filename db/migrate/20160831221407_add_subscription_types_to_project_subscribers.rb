class AddSubscriptionTypesToProjectSubscribers < ActiveRecord::Migration
  def change
    add_column :project_subscribers, :daily, :boolean, default: false, null: false
    add_column :project_subscribers, :weekly, :boolean, default: false, null: false

    ProjectSubscriber.update_all(daily: true, weekly: true)
  end
end
