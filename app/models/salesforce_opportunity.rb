# == Schema Information
#
# Table name: salesforce_opportunities
#
#  id                        :integer          not null, primary key
#  salesforce_opportunity_id :string           default(""), not null
#  salesforce_account_id     :string           default(""), not null
#  name                      :string           default(""), not null
#  description               :text
#  is_closed                 :boolean
#  is_won                    :boolean
#  stage_name                :string
#  close_date                :date
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  contextsmith_project_id   :uuid
#  probability               :decimal(5, 2)
#  expected_revenue          :decimal(14, 2)
#  amount                    :decimal(14, 2)
#  forecast_category_name    :string
#  owner_id                  :string
#
# Indexes
#
#  index_salesforce_opportunities_on_salesforce_opportunity_id  (salesforce_opportunity_id) UNIQUE
#

class SalesforceOpportunity < ActiveRecord::Base
	belongs_to	:salesforce_account, foreign_key: "salesforce_account_id", primary_key: "salesforce_account_id"
  belongs_to  :project, foreign_key: "contextsmith_project_id"

  scope :is_open, -> {where(is_closed: false)}
  # scope :is_linked, -> {where.not(contextsmith_project_id: nil)}
  scope :is_not_linked, -> {where(contextsmith_project_id: nil)}

  # This class method finds SFDC opportunities and creates a local model out of all opportunities associated with each SFDC-linked CS account.
  # Params:    query_range: The limit for SFDC query results
  # Returns:   A hash that represents the execution status/result. Consists of:
  #             status - string "SUCCESS" if load successful; otherwise, "ERROR".
  #             result - if successful, contains the # of opportunities added/updated; if an error occurred, contains the title of the error.
  #             detail - contains the details of an error.
  # TODO: This recovers if an error occurs while running a SFDC query during the process, but need to add code to save error messages.
  def self.load_opportunities(current_user, query_range=500)
    organization_id = current_user.organization_id
    val = []

    client = SalesforceService.connect_salesforce(organization_id)
    if client.nil?
      puts "** SalesforceService error: During loading SFDC opportunities, an attempt to connect to Salesforce using SalesforceService.connect_salesforce in SalesforceOpportunity.load_opportunities failed!"
      return { status: "ERROR", result: "SalesforceService Connection error", detail: "During loading SFDC opportunities, an attempt to connect to Salesforce failed." } 
    end

    total_opportunities = 0
    error_occurred = false
    if current_user.admin?
      sfdc_accounts = SalesforceAccount.where(contextsmith_organization_id: organization_id).is_linked

      sfdc_accounts.each do |a|
        query_statement = "SELECT Id, AccountId, OwnerId, Name, Amount, Description, IsWon, IsClosed, StageName, CloseDate, Probability, ForecastCategoryName from Opportunity where AccountId = '#{a.salesforce_account_id}' AND ((IsClosed = FALSE) OR (IsClosed = TRUE and CloseDate > #{(Time.now - 1.year).utc.strftime('%Y-%m-%d')})) LIMIT #{query_range}"

        query_result = SalesforceService.query_salesforce(client, query_statement)
        # puts "query_statement: #{ query_statement }" 
        # puts "query_result: #{ query_result }"
        # puts "query_result result length => #{query_result[:result].length}"
        
        if query_result[:status] == "ERROR"
          puts "** SalesforceService error: During loading SFDC opportunities, a query to Salesforce using SalesforceService.query_salesforce in SalesforceOpportunity.load_opportunities had errors!  #{ query_result[:result] } Detail: #{ query_result[:detail] }"
          error_occurred = true
        else
          query_result[:result].each do |opp|
            val << "('#{opp.Id}', 
                    '#{opp.OwnerId}', 
                    '#{opp.AccountId}', 
                    #{SalesforceOpportunity.sanitize(opp.Name)}, 
                    #{SalesforceOpportunity.sanitize(opp.Description)}, 
                    #{opp.Amount.nil? ? "0.00" : opp.Amount}, 
                    #{opp.IsClosed}, 
                    #{opp.IsWon}, 
                    #{SalesforceOpportunity.sanitize(opp.StageName)},
                    '#{opp.CloseDate}',
                    #{SalesforceOpportunity.sanitize(opp.Probability)},
                    #{SalesforceOpportunity.sanitize(opp.ForecastCategoryName)},
                    '#{Time.now}', '#{Time.now}')"
          end
        end

        insert = 'INSERT INTO "salesforce_opportunities" ("salesforce_opportunity_id", "owner_id", "salesforce_account_id", "name", "description", "amount", "is_closed", "is_won", "stage_name", "close_date", "probability", "forecast_category_name", "created_at", "updated_at") VALUES'
        on_conflict = 'ON CONFLICT (salesforce_opportunity_id) DO UPDATE SET owner_id = EXCLUDED.owner_id, salesforce_account_id = EXCLUDED.salesforce_account_id, name = EXCLUDED.name, description = EXCLUDED.description, amount = EXCLUDED.amount, is_closed = EXCLUDED.is_closed, is_won = EXCLUDED.is_won, stage_name = EXCLUDED.stage_name, close_date = EXCLUDED.close_date, probability = EXCLUDED.probability, forecast_category_name = EXCLUDED.forecast_category_name, updated_at = EXCLUDED.updated_at'
        values = val.join(', ')

        if val.present?
          SalesforceOpportunity.transaction do
            SalesforceOpportunity.connection.execute([insert,values,on_conflict].join(' '))
          end

          total_opportunities += query_result[:result].length
          val = []
        end
      end  # End: sfdc_accounts.each do |a|
    else # if !current_user.admin? (i.e., single SFDC user)
      sfdc_userid = SalesforceService.get_salesforce_user_uuid(organization_id, current_user)
      query_statements = []
      query_statements << "SELECT Id, AccountId, OwnerId, Name, Amount, Description, IsWon, IsClosed, StageName, CloseDate, Probability, ForecastCategoryName from Opportunity where OwnerId = '#{sfdc_userid}' AND ((IsClosed = FALSE) OR (IsClosed = TRUE and CloseDate > #{(Time.now - 1.year).utc.strftime('%Y-%m-%d')})) LIMIT #{query_range}"  # "Closed YTD & all Open Opps"
      # query_statements << "SELECT Id, AccountId, OwnerId, Name, Amount, Description, IsWon, IsClosed, StageName, CloseDate, Probability, ForecastCategoryName from Opportunity where OwnerId = '#{sfdc_userid}' AND IsClosed = FALSE ORDER BY CloseDate DESC LIMIT 10" # "recent 10 Open Opps"

      query_statements.each do |query_statement|
        query_result = SalesforceService.query_salesforce(client, query_statement)
        
        if query_result[:status] == "ERROR"
          puts "** SalesforceService error: During loading SFDC opportunities, query_salesforce() in SalesforceOpportunity.load_opportunities had errors!  #{ query_result[:result] } Detail: #{ query_result[:detail] }"
          error_occurred = true
        else
          query_result[:result].each do |opp|
            val << "('#{opp.Id}', 
                    '#{opp.OwnerId}', 
                    '#{opp.AccountId}', 
                    #{SalesforceOpportunity.sanitize(opp.Name)}, 
                    #{SalesforceOpportunity.sanitize(opp.Description)}, 
                    #{opp.Amount.nil? ? "0.00" : opp.Amount}, 
                    #{opp.IsClosed}, 
                    #{opp.IsWon}, 
                    #{SalesforceOpportunity.sanitize(opp.StageName)},
                    '#{opp.CloseDate}',
                    #{SalesforceOpportunity.sanitize(opp.Probability)},
                    #{SalesforceOpportunity.sanitize(opp.ForecastCategoryName)},
                    '#{Time.now}', '#{Time.now}')"
          end
          total_opportunities += query_result[:result].length
        end
      end # End: query_statements.each do |query_statement|

      insert = 'INSERT INTO "salesforce_opportunities" ("salesforce_opportunity_id", "owner_id", "salesforce_account_id", "name", "description", "amount", "is_closed", "is_won", "stage_name", "close_date", "probability", "forecast_category_name", "created_at", "updated_at") VALUES'
      on_conflict = 'ON CONFLICT (salesforce_opportunity_id) DO UPDATE SET owner_id = EXCLUDED.owner_id, salesforce_account_id = EXCLUDED.salesforce_account_id, name = EXCLUDED.name, description = EXCLUDED.description, amount = EXCLUDED.amount, is_closed = EXCLUDED.is_closed, is_won = EXCLUDED.is_won, stage_name = EXCLUDED.stage_name, close_date = EXCLUDED.close_date, probability = EXCLUDED.probability, forecast_category_name = EXCLUDED.forecast_category_name, updated_at = EXCLUDED.updated_at'
      values = val.join(', ')

      if val.present?
        SalesforceOpportunity.transaction do
          SalesforceOpportunity.connection.execute([insert,values,on_conflict].join(' '))
        end

        val = []
      end
    end

    if error_occurred
      return { status: "ERROR", result: "", detail: "" } # TODO: capture error messages above
    elsif total_opportunities > 0
      return { status: "SUCCESS", result: "#{total_opportunities} opportunities added/updated." }
    else
      return { status: "SUCCESS", result: "Warning: no opportunities added." }
    end
	end
end
