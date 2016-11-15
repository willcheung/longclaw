class SalesforceService

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
        puts "Error: salesforce connection error"
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
        puts "Error: salesforce query error.  Query: " + query_statement
      end     
    end

    return salesforce_result

  end
end