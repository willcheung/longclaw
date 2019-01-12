class AddAccountIdIndexSalesforce < ActiveRecord::Migration
  def change
  	add_index :salesforce_accounts, :contextsmith_account_id
  end
end
