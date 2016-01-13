class CreateUniqueIndexActivities < ActiveRecord::Migration
  def change
    add_index :activities, :backend_id, unique: true
  end
end
