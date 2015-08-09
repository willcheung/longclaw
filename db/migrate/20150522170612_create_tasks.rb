class CreateTasks < ActiveRecord::Migration
  def change
    create_table :tasks, id: :uuid do |t|
    	t.uuid		 :project_id
    	t.string   :name
	    t.text     :description
	    t.integer  :assignee_id
	    t.integer  :status
	    t.boolean  :is_billable,  :default => true
	    t.integer  :hourly_rate
	    t.string   :url
	    t.integer	 :estimated_hours
	    t.integer  :external_id
	    t.text		 :external_source

      t.timestamps null: false
    end
  end
end
