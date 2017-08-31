class AddDomainToTrackingEvents < ActiveRecord::Migration
  def change
    add_column :tracking_events, :domain, :string
  end
end
