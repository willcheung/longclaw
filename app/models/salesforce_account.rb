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
	belongs_to  :organiztion, foreign_key: "contextsmith_organization_id"
	belongs_to :account, foreign_key: "contextsmith_account_id"
   
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
      # client = Restforce.new :host => hostURL,
      #                        :client_id => salesforce_client_id,
      #                        :client_secret => salesforce_client_secret,
      #                        :oauth_token => salesforce_user.oauth_access_token,
      #                        :refresh_token => salesforce_user.oauth_refresh_token,
      #                        :instance_url => salesforce_user.oauth_instance_url

      client = Restforce.new :host => 'login.salesforce.com',
                            :client_id => '3MVG9Nc1qcZ7BbZ3io5S_xDYDlw5Av.e8KAfPXrKIC3WJ4_6ETfQB.UDG1z_uVxKAN7clLQYDaWV4vLtGXvZU',
                            :client_secret => '1942484012556265234',
                            :oauth_token => '00D80000000cyus!AQEAQNZEDQv4JYZFo813M_Ga6k4wAfaCQU45Lsds5KJmJJGMIZsPK.dEM5fvwJwIb5jL4R4PFdkZijWk1Czwo_C54FZwREOL',
                            :refresh_token => '5Aep861QT4b0TO85TNHK50wZyj8TyYTbKWkHyxSdT5zDCBIt_DzaoygNy8cvi.Hi9MNt1z8DHoeRv.vmfBDyKdV',
                            :instance_url => 'https://na6.salesforce.com'


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

	def self.load(current_user, save_in_db=false)
    salesforce_account_objects = []
    val = []
		client = connect_salesforce(current_user)

    if client.nil?
      return
    end

    queryRange = 20000
    firstQuery = true   
    last_Created_Id = nil

    # salesforce offset sucks, don't use it
    # if offset is larger than 2000 it will return a  NUMBER_OUTSIDE_VALID_RANGE 
    # note that apex has a limit of 50,000 records
    # meaning we can get only 50,000 at most with 1 query

    puts "--------------------start------------------------"
    puts Time.now

    while true
      if firstQuery
        query_statement = "select Id, Name, LastModifiedDate from Account ORDER BY Id LIMIT " + queryRange.to_s
        firstQuery = false
      else
        query_statement = "select Id, Name, LastModifiedDate from Account WHERE Id > '#{last_Created_Id}' ORDER BY Id LIMIT " + queryRange.to_s
      end
      puts query_statement 
      
      salesforce_accounts = query_salesforce(client, query_statement)

      puts salesforce_accounts.length
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
    
        insert = 'INSERT INTO "salesforce_accounts" ("salesforce_account_id", "salesforce_account_name", "contextsmith_organization_id", "salesforce_updated_at", "created_at", "updated_at") VALUES'
        on_conflict = 'ON CONFLICT (salesforce_account_id) DO UPDATE SET salesforce_account_name = EXCLUDED.salesforce_account_name, contextsmith_organization_id = EXCLUDED.contextsmith_organization_id, salesforce_updated_at = EXCLUDED.salesforce_updated_at'
        values = val.join(', ')

        if !val.empty? and save_in_db
          SalesforceAccount.transaction do
            # Insert activities into database
            SalesforceAccount.connection.execute([insert,values,on_conflict].join(' '))
          end
        end

        sleep(20)
      end
    end

    puts Time.now
    puts "--------------------end------------------------"
	end
end
