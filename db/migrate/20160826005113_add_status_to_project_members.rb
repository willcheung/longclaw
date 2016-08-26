class AddStatusToProjectMembers < ActiveRecord::Migration
  def change
    add_column :project_members, :status, :integer, limit: 1, null: false, default: 0

    ProjectMember.update_all(status: 2)
  end
end
