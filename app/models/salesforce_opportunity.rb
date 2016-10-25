# == Schema Information
#
# Table name: salesforce_opportunities
#
#  id                        :integer          not null, primary key
#  salesforce_opportunity_id :string           default(""), not null
#  salesforce_account_id     :string           default(""), not null
#  name                      :string           default(""), not null
#  description               :text
#  amount                    :decimal(8, 2)
#  is_closed                 :boolean
#  is_won                    :boolean
#  stage_name                :string
#  close_date                :date
#  renewal_date              :date
#  contract_start_date       :date
#  contract_end_date         :date
#  contract_arr              :decimal(8, 2)
#  contract_mrr              :decimal(8, 2)
#  custom_fields             :hstore
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#
# Indexes
#
#  index_salesforce_opportunities_on_custom_fields              (custom_fields)
#  index_salesforce_opportunities_on_salesforce_opportunity_id  (salesforce_opportunity_id) UNIQUE
#

class SalesforceOpportunity < ActiveRecord::Base
	belongs_to	:salesforce_account, foreign_key: "salesforce_account_id"

	def self.load(current_user, query_range=500)
		val = []

		client = SalesforceAccount.connect_salesforce(current_user)
    return if client.nil?

    sfdc_accounts = SalesforceAccount.where(contextsmith_organization_id: current_user.organization_id).is_linked

    sfdc_accounts.each do |a|
    	query_statement = "select Id, AccountId, Name, Amount, Description, IsWon, IsClosed, StageName, CloseDate from Opportunity where AccountId = '#{a.salesforce_account_id}' and StageName != 'Closed Lost' ORDER BY Id"

    	opportunities = SalesforceAccount.query_salesforce(client, query_statement)

    	opportunities.each do |opp|
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
        val = []
      end

    end
	end
end
