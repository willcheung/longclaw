class CreateTimesheets < ActiveRecord::Migration
  def change
    create_table :timesheets, id: :uuid do |t|
    	t.uuid		:user_id
    	t.integer	:calendar_week
    	t.string	:year
    	t.string	:status

      t.timestamps null: false
    end
  end
end
