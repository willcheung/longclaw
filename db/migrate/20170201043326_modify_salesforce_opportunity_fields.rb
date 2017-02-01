class ModifySalesforceOpportunityFields < ActiveRecord::Migration
  def change
  	remove_column :salesforce_opportunities, :renewal_date, :date
  	remove_column :salesforce_opportunities, :contract_end_date, :date
  	remove_column :salesforce_opportunities, :contract_start_date, :date
  	remove_column :salesforce_opportunities, :contract_arr, :decimal, :precision => 14, :scale => 2
  	remove_column :salesforce_opportunities, :contract_mrr, :decimal, :precision => 12, :scale => 2

  	# Remove custom fields
  	remove_column	:salesforce_opportunities, :custom_fields, :hstore
  	remove_column :salesforce_accounts, :custom_fields, :hstore

  	# Add more SFDC fields
  	add_column 		:salesforce_opportunities, :probability, :decimal, :precision => 5, :scale => 2
  	add_column		:salesforce_opportunities, :expected_revenue, :decimal, :precision => 14, :scale => 2
  	
  	# Add fields not typically in SFDC
  	add_column		:projects, :renewal_date, :date
  	add_column		:projects, :contract_start_date, :date
  	add_column		:projects, :contract_end_date, :date
  	add_column		:projects, :contract_arr, :decimal, :precision => 14, :scale => 2
  	add_column 		:projects, :contract_mrr, :decimal, :precision => 12, :scale => 2
  	add_column 		:projects, :renewal_count, :integer
  	add_column 		:projects, :has_case_study, :boolean, default: false, null: false
  	add_column 		:projects, :is_referenceable, :boolean, default: false, null: false
  	add_column 		:accounts, :revenue_potential, :decimal, :precision => 14, :scale => 2

  	# Change Contact field
  	rename_column :contacts, :alt_email, :source
  end
end
