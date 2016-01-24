class AddPinsToActivities < ActiveRecord::Migration
  def change
  	add_column :activities, :is_pinned, :boolean, :default => false
  	add_column :activities, :pinned_by, :uuid
  	add_column :activities, :pinned_at, :datetime
  end
end
