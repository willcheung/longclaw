class CreateConversationsAndMessages < ActiveRecord::Migration
  def change
    create_table :conversations do |t|
    	t.string :backend_id, null: false
    	t.integer :project_id #foriegn key

    	t.string :subject, null: false
    	t.datetime :last_sent_date, null: false
    	t.string :last_sent_date_epoch, null: false

    	t.text :external_members, null: false
    	t.text :internal_members, null: false

    	t.timestamps null: false
    end

    create_table :messages do |t|
    	t.string :mime_message_id, null: false
    	t.string :gmail_message_id, null: false
    	t.integer :conversation_id #foriegn key

    	t.string :subject, null: false
    	t.string :sent_date_epoch, null: false
    	t.datetime :sent_date, null: false
    	t.text :preview_content

    	t.text :to, null: false
    	t.text :from, null: false
    	t.text :cc, null: false, default: ""

    	t.timestamps null: false
    end
  end
end
