class ChangeOrganizationOwnerIdToUuid < ActiveRecord::Migration
  def change
  	remove_column :organizations, :owner_id
  	add_column :organizations, :owner_id, :uuid
  end
end
