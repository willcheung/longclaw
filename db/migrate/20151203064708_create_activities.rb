class CreateActivities < ActiveRecord::Migration
  def change
    create_table :activities do |t|
        t.string :category, null: false
    	t.string :title, null: false
        t.text :note, null: false, default: ''
        t.boolean :is_public, null: false, default: true

        # Emails
        t.string :backend_id, default: nil
    	t.datetime :last_sent_date, default: nil
    	t.string :last_sent_date_epoch, default: nil
    	t.jsonb :from, null: false, default: '{}'
    	t.jsonb :to, null: false, default: '{}'
        t.jsonb :cc, null: false, default: '{}'
        t.jsonb :email_messages, null: false, default: '{}'

        t.uuid :project_id, null: false # foreign key
        t.uuid :posted_by, null: false # foregin key

    	t.timestamps null: false
    end

    add_index  :activities, :email_messages, using: :gin

    rename_column :projects, :actual_start_date, :start_date
    rename_column :projects, :actual_end_date, :end_date
    remove_column :projects, :planned_start_date, :date
    remove_column :projects, :planned_end_date, :date
  end
end
