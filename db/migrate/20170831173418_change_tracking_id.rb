class ChangeTrackingId < ActiveRecord::Migration
  def change
    change_column :tracking_events, :tracking_id, :string
    change_column :tracking_requests, :tracking_id, :string
  end
end
