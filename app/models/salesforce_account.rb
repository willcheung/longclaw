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
	belongs_to :organization, foreign_key: "contextsmith_organization_id"
	belongs_to :account, foreign_key: "contextsmith_account_id"
  has_many :salesforce_opportunities, -> { order("close_date desc") }, primary_key: "salesforce_account_id", dependent: :destroy

  scope :is_linked, -> {where("contextsmith_account_id is not null")}

  validates :salesforce_account_name, presence: true

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
  # Params:    query_range: The limit for SFDC query results
  # Returns:   A hash that represents the execution status/result. Consists of:
  #             status - string "SUCCESS" if load successful; otherwise, "ERROR".
  #             result - if successful, contains the # of accounts added/updated; if an error occurred, contains the title of the error.
  #             detail - details of any errors.
  # Note: This will not recover (will abort) if an error occurs while running query SFDC during the process -- if it will happen, likely will happen on first run not in middle of subsequent runs.
  def self.load_accounts(current_user, query_range=500)
    organization_id = current_user.organization_id
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
        puts "** SalesforceService error: During loading SFDC accounts, query_salesforce() in SalesforceAccount.load_accounts had errors!  #{ query_result[:result] } Detail: #{ query_result[:detail] }"
        return { status: "ERROR", result: query_result[:result], detail: "During loading SFDC accounts, a query to Salesforce had errors. Detail: #{query_result[:detail]}" } 
      end
      break if query_result[:result].length == 0  # batch loop is completed
        
      query_result[:result].each do |s|
        last_Created_Id = s.Id if last_Created_Id.nil? || last_Created_Id < s.Id

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
      return { status: "SUCCESS", result: "#{total_accounts} accounts added/updated." }
    else
      return { status: "SUCCESS", result: "Warning: no accounts added." }
    end
	end

  # For salesforce_account, updates the local copy and pushes change to Salesforce
  def self.update_all_salesforce(client: , salesforce_account: , fields: , current_user: )
    # return { status: "ERROR", result: "Simulated SFDC error", detail: "Simulated detail" }
    return { status: "ERROR", result: "ContextSmith Error", detail: "Parameter passed to an internal function is invalid." } if client.nil?

    return { status: "ERROR", result: "Salesforce account update error", detail: "Salesforce account does not exist or this user does not exist." } if salesforce_account.blank? || current_user.blank?

    if salesforce_account.organization == current_user.organization
      # puts "\n\nUpdating #{salesforce_account.salesforce_account_name}.... "

      #TODO: Make update of CS and SFDC a single Unit of work (2 phase commit?)
      # Update Contextsmith model
      begin
        salesforce_account.update(salesforce_account_name: fields[:salesforce_account_name])
      rescue => e
        return { status: "ERROR", result: "Salesforce account update error", detail: e.to_s }
      end

      # Update Salesforce
      # Put the fields and values to be updated into a hash object.
      sObject_meta = { id: salesforce_account.salesforce_account_id, type: "account" }
      sObject_fields = { name: fields[:salesforce_account_name] }
      update_result = SalesforceService.update_salesforce(client: client, update_type: "account", sObject_meta: sObject_meta, sObject_fields: sObject_fields)

      if update_result[:status] == "SUCCESS"
        puts "-> SFDC account was updated from a ContextSmith salesforce_account. SFDC Account Id='#{ salesforce_account.salesforce_account_id }'."
      else  # Salesforce update failure
        puts "****SFDC****: Salesforce error in SalesforceAccount.update_all_salesforce().  #{update_result[:result]}  Details: #{ update_result[:detail] }."
        return { status: "ERROR", result: update_result[:result], detail: update_result[:detail] + " sObject_fields=#{ sObject_fields }" } 
      end
    else # End: if salesforce_account.organization == current_user.organization
      return { status: "ERROR", result: "Salesforce account update error", detail: "Salesforce account does not exist or this user does not have access to it." } 
    end

    return { status: "SUCCESS", result: "Update completed." }
  end

  # Native and custom CS fields are updated according to the explicit mapping of a field of a SFDC account to a field of a CS account, for all active accounts in current_user's organization. Process aborts immediately if there is an update/SFDC error.
  # TODO: Refactor so that we only go through active accounts that have salesforce accounts (owned by this user) linked to it, for performance.
  def self.refresh_fields(current_user)
    accounts = current_user.organization.accounts.where(status: "Active")
    account_standard_fields = EntityFieldsMetadatum.get_sfdc_fields_mapping_for(organization_id: current_user.organization_id, entity_type: EntityFieldsMetadatum::ENTITY_TYPE[:Account])
    account_custom_fields = CustomFieldsMetadatum.where("organization_id = ? AND entity_type = ? AND salesforce_field is not null", current_user.organization_id, CustomFieldsMetadatum.validate_and_return_entity_type(CustomFieldsMetadatum::ENTITY_TYPE[:Account], true))
    # puts "any accounts mapped?=#{accounts.find{|a| a.salesforce_accounts.present?}.present?}"
    # puts "\n\naccount_standard_fields: #{account_standard_fields}\naccount_custom_fields: #{account_custom_fields}\n"

    unless accounts.blank? || current_user.organization.salesforce_accounts.where.not(contextsmith_account_id: nil).first.blank? || (account_standard_fields.blank? && account_custom_fields.blank?) # nothing to do if no active CS accounts, no SFDC accounts mapped, or no account field mappings are found
      @client = SalesforceService.connect_salesforce(current_user.organization_id)
      #@client=nil # simulates a Salesforce connection error

      unless @client.nil?  # unless SFDC connection error
        # standard fields
        update_result = Account.update_fields_from_sfdc(client: @client, accounts: accounts, sfdc_fields_mapping: account_standard_fields)
        if update_result[:status] == "ERROR"
          detail = {}
          detail[:failure_method_location] = "Account.update_fields_from_sfdc()"
          detail[:error_detail] = "Error while attempting to load standard fields from Salesforce Accounts.  #{ update_result[:result] } Details: #{ update_result[:detail] }"
          return { status: "ERROR", result: "Update error", detail: detail }
        end

        # custom fields
        accounts.each do |a|
          unless a.salesforce_accounts.first.nil? 
            # puts "**** SFDC account:\"#{a.salesforce_accounts.first.salesforce_account_name}\" --> CS account:\"#{a.name}\" ****\n"
            load_result = Account.load_salesforce_fields(client: @client, account_id: a.id, sfdc_account_id: a.salesforce_accounts.first.salesforce_account_id, account_custom_fields: account_custom_fields)

            if load_result[:status] == "ERROR"
              detail = {}
              detail[:failure_method_location] = "Account.load_salesforce_fields()"
              detail[:error_detail] = "Error while attempting to load fields from Salesforce Account \"#{a.salesforce_accounts.first.salesforce_account_name}\" (sfdc_id='#{a.salesforce_accounts.first.salesforce_account_id}') to CS Account \"#{a.name}\" (account_id='#{a.id}').  #{ load_result[:result] } Details: #{ load_result[:detail] }"
              return { status: "ERROR", result: "Update error", detail: detail }
            end
          end
        end # End: accounts.each do |s|
      else
        puts "****SFDC****: Salesforce error in SalesforceAccount.refresh_fields: Cannot establish a connection!"
        return { status: "ERROR", result: SalesforceController::ERRORS[:SalesforceConnectionError], detail: "Unable to connect to Salesforce." }
      end
    else # no active CS accounts, no SFDC accounts mapped, and no account field mappings found
      return { status: "SUCCESS", result: "Warning: no accounts updated." }
    end

    return { status: "SUCCESS", result: "Refresh completed." }
  end
end
