class CreateTrackingSettings < ActiveRecord::Migration
  def change
    create_table :tracking_settings do |t|
      t.uuid :user_id
      t.datetime :last_seen
      t.timestamps null: false
    end
  end
end
