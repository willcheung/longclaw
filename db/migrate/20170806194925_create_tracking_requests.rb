class CreateTrackingRequests < ActiveRecord::Migration
  def change
    create_table :tracking_requests do |t|
      t.uuid :user_id
      t.string :tracking_id, limit: 255
      t.string :message_id, limit: 255
      t.string :subject
      t.text :recipients, array: true, default: []
      t.string  :status
      t.datetime :sent_at
      t.string :email_id
      t.timestamps null: false
    end
  end
end
