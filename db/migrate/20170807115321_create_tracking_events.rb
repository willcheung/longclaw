class CreateTrackingEvents < ActiveRecord::Migration
  def change
    create_table :tracking_events do |t|
      t.string :tracking_id
      t.datetime :date
      t.string :user_agent
      t.string :place_name
      t.string :event_type

      t.timestamps null: false
    end
  end
end
