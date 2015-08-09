class CreateProjectMembers < ActiveRecord::Migration
  def change
    create_table :project_members, id: :uuid do |t|
    	t.uuid	:project_id
    	t.uuid	:contact_id

      t.timestamps null: false
    end
  end
end
