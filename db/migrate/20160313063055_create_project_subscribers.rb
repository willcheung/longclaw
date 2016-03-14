class CreateProjectSubscribers < ActiveRecord::Migration
  def change
    create_table :project_subscribers do |t|
    	t.uuid	:project_id
    	t.uuid	:user_id

      t.timestamps null: false
    end

  	add_index "project_subscribers", ["project_id"], name: "index_project_subscribers_on_project_id", using: :btree
  	add_index "project_subscribers", ["user_id"], name: "index_project_subscribers_on_email", using: :btree
  end
end
