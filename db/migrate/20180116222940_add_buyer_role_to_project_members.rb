class AddBuyerRoleToProjectMembers < ActiveRecord::Migration
  def change
    add_column :project_members, :buyer_role, :string
  end
end
