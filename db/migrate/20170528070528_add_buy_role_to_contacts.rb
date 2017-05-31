class AddBuyRoleToContacts < ActiveRecord::Migration
  def change
  	add_column :contacts, :buyer_role, :string
  	
  	# Clean up unsed fields
  	remove_column :projects, :project_code, :string
  	remove_column :projects, :budgeted_hours, :integer
  	remove_column :projects, :contract_mrr, :decimal, :precision => 12, :scale => 2
  	remove_column :projects, :start_date, :date
  	remove_column :projects, :end_date, :date
  	
  	# Add more SFDC Opportunity fields
  	add_column :projects, :amount, :decimal, :precision => 14, :scale => 2
  	add_column :projects, :stage, :string
  	add_column :projects, :close_date, :date
  	add_column :projects, :expected_revenue, :decimal, :precision => 14, :scale => 2
  end
end
