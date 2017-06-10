# == Schema Information
#
# Table name: salesforce_opportunities
#
#  id                        :integer          not null, primary key
#  salesforce_opportunity_id :string           default(""), not null
#  salesforce_account_id     :string           default(""), not null
#  name                      :string           default(""), not null
#  description               :text
#  amount                    :decimal(14, 2)
#  is_closed                 :boolean
#  is_won                    :boolean
#  stage_name                :string
#  close_date                :date
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  contextsmith_project_id   :uuid
#  probability               :decimal(5, 2)
#  expected_revenue          :decimal(14, 2)
#
# Indexes
#
#  index_salesforce_opportunities_on_salesforce_opportunity_id  (salesforce_opportunity_id) UNIQUE
#

class SalesforceOpportunity < ActiveRecord::Base
	belongs_to	:salesforce_account, foreign_key: "salesforce_account_id", primary_key: "salesforce_account_id"
  belongs_to  :project, foreign_key: "contextsmith_project_id"

  # This class method finds SFDC opportunities and creates a local model
  # Returns:   A hash that represents the execution status/result. Consists of:
  #             status - string "SUCCESS" if load successful; otherwise, "ERROR".
  #             result - if successful, contains the # of opportunities added/updated; if an error occurred, contains the title of the error.
  #             detail - contains the details of an error.
  def self.load_opportunities(organization_id, query_range=500)
    val = []

    client = SalesforceService.connect_salesforce(organization_id)
    if client.nil?
      puts "** SalesforceService error: During loading SFDC opportunities, an attempt to connect to Salesforce using SalesforceService.connect_salesforce in SalesforceOpportunity.load_opportunities failed!"
      return { status: "ERROR", result: "SalesforceService Connection error", detail: "During loading SFDC opportunities, an attempt to connect to Salesforce failed." } 
    end

    sfdc_accounts = SalesforceAccount.where(contextsmith_organization_id: organization_id).is_linked
    total_opportunities = 0

    sfdc_accounts.each do |a|
      query_statement = "select Id, AccountId, Name, Amount, Description, IsWon, IsClosed, StageName, CloseDate from Opportunity where AccountId = '#{a.salesforce_account_id}' and StageName != 'Closed Lost' ORDER BY Id"

      query_result = SalesforceService.query_salesforce(client, query_statement)
      # puts "query_statement: #{ query_statement }" 
      # puts "query_result: #{ query_result }"
      # puts "query_result result length => #{query_result[:result].length}"
      
      if query_result[:status] == "ERROR"
        puts "** SalesforceService error: During loading SFDC opportunities, a query to Salesforce using SalesforceService.query_salesforce in SalesforceOpportunity.load_opportunities had errors!  #{ query_result[:result] } Detail: #{ query_result[:detail] }"
        return { status: "ERROR", result: query_result[:result], detail: "During loading SFDC opportunities, a query to Salesforce had errors. Detail: #{ query_result[:detail] }" } 
      end

    	query_result[:result].each do |opp|
    		val << "('#{opp.Id}', 
    						'#{opp.AccountId}', 
    						#{SalesforceOpportunity.sanitize(opp.Name)}, 
    						#{SalesforceOpportunity.sanitize(opp.Description)}, 
    						#{opp.Amount.nil? ? "0.00" : opp.Amount}, 
    						#{opp.IsClosed}, 
    						#{opp.IsWon}, 
    						#{SalesforceOpportunity.sanitize(opp.StageName)},
    						'#{opp.CloseDate}',
    						'#{Time.now}', '#{Time.now}')"
    	end

    	insert = 'INSERT INTO "salesforce_opportunities" ("salesforce_opportunity_id", "salesforce_account_id", "name", "description", "amount", "is_closed", "is_won", "stage_name", "close_date", "created_at", "updated_at") VALUES'
    	on_conflict = 'ON CONFLICT (salesforce_opportunity_id) DO UPDATE SET salesforce_account_id = EXCLUDED.salesforce_account_id, name = EXCLUDED.name, description = EXCLUDED.description, amount = EXCLUDED.amount, is_closed = EXCLUDED.is_closed, is_won = EXCLUDED.is_won, stage_name = EXCLUDED.stage_name, close_date = EXCLUDED.close_date, updated_at = EXCLUDED.updated_at'
      values = val.join(', ')

      if !val.empty?
        SalesforceOpportunity.transaction do
          SalesforceOpportunity.connection.execute([insert,values,on_conflict].join(' '))
        end

        total_opportunities += query_result[:result].length
        val = []
      end
    end  # End: sfdc_accounts.each do |a|

    if total_opportunities > 0
      return { status: "SUCCESS", result: "#{total_opportunities} opportunities added/updated." }
    else
      return { status: "SUCCESS", result: "Warning: no opportunities added." }
    end
	end
end
