class RecreateUniqueIndexActivities < ActiveRecord::Migration
  def change
    remove_index :activities, column: [:backend_id, :project_id]
    add_index :activities, [:category, :backend_id, :project_id], unique: true
  end
end
