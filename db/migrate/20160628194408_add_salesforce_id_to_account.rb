class AddSalesforceIdToAccount < ActiveRecord::Migration
  def change
  	add_column :accounts, :salesforce_id, :string, default:""
  end
end
