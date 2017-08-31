class AddTrackingIndices < ActiveRecord::Migration
  def change
    add_index :tracking_events, :tracking_id
    add_index :tracking_requests, :tracking_id
  end
end
