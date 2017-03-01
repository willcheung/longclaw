class SalesforceService

  def self.connect_salesforce(organization_id)
    salesforce_client_id = ENV['salesforce_client_id']
    salesforce_client_secret = ENV['salesforce_client_secret'] 
    hostURL = 'login.salesforce.com'  
    # try to get salesforce production. if not connect, check if it is connected to salesforce sandbox
    salesforce_user = OauthUser.find_by(oauth_provider: 'salesforce', organization_id: organization_id)

    if(salesforce_user.nil?)
      salesforce_user = OauthUser.find_by(oauth_provider: 'salesforcesandbox', organization_id: organization_id)
      salesforce_client_id = ENV['salesforce_sandbox_client_id']
      salesforce_client_secret = ENV['salesforce_sandbox_client_secret']
      hostURL = 'test.salesforce.com' 
    end

    client = nil
    if(!salesforce_user.nil?)  
      # Restforce gem automatically refresh access token if expired       
      client = Restforce.new(host: hostURL,
                             client_id: salesforce_client_id,
                             client_secret: salesforce_client_secret,
                             oauth_token: salesforce_user.oauth_access_token,
                             refresh_token: salesforce_user.oauth_refresh_token,
                             authentication_callback: Proc.new { |x| puts x.to_s },
                             instance_url: salesforce_user.oauth_instance_url,
                             api_version: '38.0')
      begin
        client.user_info
      rescue
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