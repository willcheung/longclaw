class AddStatusToProjectMembers < ActiveRecord::Migration
  def change
    add_column :project_members, :status, :integer, limit: 1, null: false, default: 1
  end
end
