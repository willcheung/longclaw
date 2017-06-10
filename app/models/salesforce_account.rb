# == Schema Information
#
# Table name: salesforce_accounts
#
#  id                           :integer          not null, primary key
#  salesforce_account_id        :string           default(""), not null
#  salesforce_account_name      :string           default(""), not null
#  salesforce_updated_at        :datetime
#  contextsmith_account_id      :uuid
#  contextsmith_organization_id :uuid             not null
#  created_at                   :datetime         not null
#  updated_at                   :datetime         not null
#
# Indexes
#
#  index_salesforce_accounts_on_salesforce_account_id  (salesforce_account_id) UNIQUE
#

class SalesforceAccount < ActiveRecord::Base
	belongs_to  :organization, foreign_key: "contextsmith_organization_id"
	belongs_to :account, foreign_key: "contextsmith_account_id"
  has_many :salesforce_opportunities, -> { order("close_date desc") }, primary_key: "salesforce_account_id", dependent: :destroy

  scope :is_linked, -> {where("contextsmith_account_id is not null")}

  #################################################################################################
  # salesforce offset sucks, don't use it
  # if offset is larger than 2000 it will return a  NUMBER_OUTSIDE_VALID_RANGE 
  # Apex has a limit of 50,000 records
  # meaning we can get only 50,000 at most in 1 query
  # 
  # 
  # Heroku statics     | memory per transaction|
  # query_range: 1000   | 36.1M                 |
  # query_range: 500    | 12.4M                 |
  # 
  # query_range higher than 1000 may cause Error R14 (Memory quota exceeded) on heroku
  # 
  # 
  # for 26,394 records of salesforce data, the processing time is about 28.2 s
  # records more than this may cause time out error on heroku (code=H12 desc="Request timeout")
  # although Heroku will still execute the task, but will return a error page on client side
  # please use ajax or asynchronous or background job instead
  #
  # 
  # to make sure memory is always released right alway
  # GC is forced on every transaction
  # to see GC status, use GC::Profiler.result
  # 
  # because transaction size is only 500 records
  # sleep is not necessary after each transaction
  # 
  # 
  ################################################################################################## 
  # This class method finds SFDC accounts and creates a local model
  # Returns:   A hash that represents the execution status/result. Consists of:
  #             status - string "SUCCESS" if load successful; otherwise, "ERROR".
  #             result - if successful, contains the # of accounts added/updated; if an error occurred, contains the title of the error.
  #             detail - details of any errors.
	def self.load_accounts(organization_id, query_range=500)
		client = SalesforceService.connect_salesforce(organization_id)
    if client.nil?
      puts "** SalesforceService error: During loading SFDC accounts, an attempt to connect to Salesforce using SalesforceService.connect_salesforce in SalesforceAccount.load_accounts failed!"
      return { status: "ERROR", result: "SalesforceService Connection error", detail: "During loading SFDC accounts, an attempt to connect to Salesforce failed." } 
    end

    firstQuery = true   
    last_Created_Id = nil
    total_accounts = 0

    # GC::Profiler.enable
    # GC::Profiler.clear

    while true
      # Query salesforce
      if firstQuery
        query_statement = "select Id, Name, LastModifiedDate from Account ORDER BY Id LIMIT #{query_range.to_s}"
        firstQuery = false
      else
        query_statement = "select Id, Name, LastModifiedDate from Account WHERE Id > '#{last_Created_Id}' ORDER BY Id LIMIT #{query_range.to_s}"
      end
      
      query_result = SalesforceService.query_salesforce(client, query_statement)
      # puts "query_statement: #{ query_statement }" 
      # puts "query_result: #{ query_result }"
      # puts "# of query_result accounts this loop => #{query_result[:result].length}"

      # call GC
      salesforce_account_objects = []
      val = []

      GC.start
      # puts "Garbage Count => #{GC.count}"
      # puts "result => #{GC::Profiler.result}"

      # start transaction
      if query_result[:status] == "ERROR"
        puts "** SalesforceService error: During loading SFDC accounts, a query to Salesforce using SalesforceService.query_salesforce in SalesforceAccount.load_accounts had errors!  #{ query_result[:result] } Detail: #{ query_result[:detail] }"
        return { status: "ERROR", result: query_result[:result], detail: "During loading SFDC accounts, a query to Salesforce had errors. Detail: #{query_result[:detail]}" } 
      end
      break if query_result[:result].length == 0  # batch loop is completed
        
      query_result[:result].each do |s|
        if last_Created_Id.nil?
          last_Created_Id = s.Id
        elsif last_Created_Id < s.Id
          last_Created_Id = s.Id
        end

        salesforce_updated_at = DateTime.strptime(s.LastModifiedDate, '%Y-%m-%dT%H:%M:%S.%L%z').to_time    
        val << "('#{s.Id}', #{SalesforceAccount.sanitize(s.Name)}, '#{organization_id}', '#{salesforce_updated_at}','#{Time.now}', '#{Time.now}' )"

        salesforce_account_objects << SalesforceAccount.new(salesforce_account_id: s.Id,
                                                            salesforce_account_name: s.Name,
                                                            contextsmith_organization_id: organization_id,
                                                            salesforce_updated_at: salesforce_updated_at)    
      end

      # puts "val.length => #{val.length}"
      # puts "salesforce_account_objects.length => #{salesforce_account_objects.length}"
  
      insert = 'INSERT INTO "salesforce_accounts" ("salesforce_account_id", "salesforce_account_name", "contextsmith_organization_id", "salesforce_updated_at", "created_at", "updated_at") VALUES'
      on_conflict = 'ON CONFLICT (salesforce_account_id) DO UPDATE SET salesforce_account_name = EXCLUDED.salesforce_account_name, contextsmith_organization_id = EXCLUDED.contextsmith_organization_id, salesforce_updated_at = EXCLUDED.salesforce_updated_at'
      values = val.join(', ')

      if !val.empty?
        SalesforceAccount.transaction do
          # Insert activities into database
          SalesforceAccount.connection.execute([insert,values,on_conflict].join(' '))
        end

        total_accounts += query_result[:result].length
        val = []
      end
    end # End: while true

    if total_accounts > 0
      return { status: "SUCCESS", result: "#{total_accounts} accounts added/updated.", detail: nil }
    else
      return { status: "SUCCESS", result: "Warning: no accounts added." }
    end
	end
end
