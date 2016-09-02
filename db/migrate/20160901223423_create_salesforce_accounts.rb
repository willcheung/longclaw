class CreateSalesforceAccounts < ActiveRecord::Migration
  def change
    create_table :salesforce_accounts do |t|
    	t.string :salesforce_account_id,     null: false, default: ""
    	t.string :salesforce_account_name,     null: false, default: ""
    	t.datetime :salesforce_updated_at, default: nil
    	t.uuid :contextsmith_account_id
    	t.uuid :contextsmith_organization_id, null:false

      t.timestamps null: false
    end

    add_index :salesforce_accounts, :salesforce_account_id, unique: true

  end  
end
