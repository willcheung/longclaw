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
#  custom_fields                :hstore
#
# Indexes
#
#  index_salesforce_accounts_on_custom_fields          (custom_fields)
#  index_salesforce_accounts_on_salesforce_account_id  (salesforce_account_id) UNIQUE
#

class SalesforceAccount < ActiveRecord::Base
	belongs_to  :organiztion, foreign_key: "contextsmith_organization_id"
	belongs_to :account, foreign_key: "contextsmith_account_id"
  has_many :salesforce_opportunities, -> { order("close_date desc") }, primary_key: "salesforce_account_id"

  scope :is_linked, -> {where("contextsmith_account_id is not null")}
   
  def self.connect_salesforce(current_user)
    salesforce_client_id = ENV['salesforce_client_id']
    salesforce_client_secret = ENV['salesforce_client_secret'] 
    hostURL = 'login.salesforce.com'  
    # try to get salesforce production. if not connect, check if it is connected to salesforce sandbox
    salesforce_user = OauthUser.find_by(oauth_provider: 'salesforce', organization_id: current_user.organization_id)

    if(salesforce_user.nil?)
      salesforce_user = OauthUser.find_by(oauth_provider: 'salesforcesandbox', organization_id: current_user.organization_id)
      salesforce_client_id = ENV['salesforce_sandbox_client_id']
      salesforce_client_secret = ENV['salesforce_sandbox_client_secret']
      hostURL = 'test.salesforce.com' 
    end

    client = nil
    if(!salesforce_user.nil?)         
      client = Restforce.new :host => hostURL,
                             :client_id => salesforce_client_id,
                             :client_secret => salesforce_client_secret,
                             :oauth_token => salesforce_user.oauth_access_token,
                             :refresh_token => salesforce_user.oauth_refresh_token,
                             :instance_url => salesforce_user.oauth_instance_url
      begin
        client.user_info
      rescue  
        # salesforce refresh token expires when different app use it for 5 times
        salesforce_user.destroy
        client = nil
        puts "Error: salesforce error"
      end      
    end

    return client

  end

  def self.query_salesforce(client, query_statement)
    salesforce_result = nil

    if(!client.nil?)          
      begin
        salesforce_result = client.query(query_statement)
      rescue  
        salesforce_result = nil
        puts "Error: salesforce " + query_statement + " error"
      end     
    end

    return salesforce_result

  end

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
	def self.load(current_user, query_range=500)
		client = connect_salesforce(current_user)
    return if client.nil?


    firstQuery = true   
    last_Created_Id = nil

    # GC::Profiler.enable
    # GC::Profiler.clear


    while true
      # Query salesforce
      if firstQuery
        query_statement = "select Id, Name, LastModifiedDate from Account ORDER BY Id LIMIT " + query_range.to_s
        firstQuery = false
      else
        query_statement = "select Id, Name, LastModifiedDate from Account WHERE Id > '#{last_Created_Id}' ORDER BY Id LIMIT " + query_range.to_s
      end
      
      salesforce_accounts = query_salesforce(client, query_statement)

      # puts query_statement 
      # puts "salesforce_accounts.length => #{salesforce_accounts.length}"

      # call GC
      salesforce_account_objects = []
      val = []

      GC.start
      # puts "Garbage Count => #{GC.count}"
      # puts "result => #{GC::Profiler.result}"

      # start transaction
      if salesforce_accounts.nil? or salesforce_accounts.length==0 
        break
      else  
        salesforce_accounts.each do |s|
          if last_Created_Id.nil?
            last_Created_Id = s.Id
          elsif last_Created_Id < s.Id
            last_Created_Id = s.Id
          end

          salesforce_updated_at = DateTime.strptime(s.LastModifiedDate, '%Y-%m-%dT%H:%M:%S.%L%z').to_time    
          val << "('#{s.Id}', #{SalesforceAccount.sanitize(s.Name)}, '#{current_user.organization_id}', '#{salesforce_updated_at}','#{Time.now}', '#{Time.now}' )"

          salesforce_account_objects << SalesforceAccount.new(salesforce_account_id: s.Id,
                                                              salesforce_account_name: s.Name,
                                                              contextsmith_organization_id: current_user.organization_id,
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

          val = []
        end
      end
    end
	end
end
