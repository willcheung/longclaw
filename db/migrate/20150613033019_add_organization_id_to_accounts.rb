class AddOrganizationIdToAccounts < ActiveRecord::Migration
  def change
  	add_column :accounts, :organization_id, :uuid
  	add_column :accounts, :notes, :text
  	add_column :accounts, :status, :string
  end
end
