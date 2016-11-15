class AddContextsmithProjectIdToSalesforceOpp < ActiveRecord::Migration
  def change
  	add_column :salesforce_opportunities, :contextsmith_project_id, :uuid
  end
end
