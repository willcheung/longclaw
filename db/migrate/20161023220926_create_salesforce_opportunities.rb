class CreateSalesforceOpportunities < ActiveRecord::Migration
  def change
  	enable_extension "hstore"

    create_table :salesforce_opportunities do |t|
    	t.string 	:salesforce_opportunity_id, null: false, default: ""
    	t.string	:salesforce_account_id, null: false, default: ""
    	t.string 	:name, null: false, default: ""
    	t.text		:description
    	t.decimal :amount, :precision => 8, :scale => 2
    	t.boolean :is_closed
    	t.boolean :is_won
    	t.string	:stage_name
    	t.date  	:close_date
    	t.date		:renewal_date
    	t.date 		:contract_start_date
    	t.date 		:contract_end_date
    	t.decimal :contract_arr, :precision => 8, :scale => 2
    	t.decimal	:contract_mrr, :precision => 8, :scale => 2
    	t.hstore	:custom_fields

      t.timestamps null: false
    end

    add_column :salesforce_accounts, :custom_fields, :hstore
    remove_column :accounts, :salesforce_id, :string

    add_index :salesforce_opportunities, :salesforce_opportunity_id, unique: true
    add_index :salesforce_opportunities, :custom_fields, using: :gin
    add_index :salesforce_accounts, :custom_fields, using: :gin
  end
end
