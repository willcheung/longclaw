class CreateNotifications < ActiveRecord::Migration
  def change
    create_table :notifications do |t|
    	t.string :category, null: false, default: "To-do"
      t.string :name
      t.text :description
      t.string :message_id
      t.uuid     :project_id
      t.string :conversation_id
      t.datetime :sent_date
      t.datetime :original_due_date
      t.datetime :remind_date
      t.boolean :is_complete, null: false, default: false
      t.boolean :has_time, null: false, default: false
      t.integer  :content_offset, default: -1, null: false
      t.datetime :complete_date
      t.uuid :assign_to
      t.uuid :completed_by
      t.string :label

      t.timestamps null: false


    end
  end
end
