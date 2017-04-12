class SalesforceService

  def self.connect_salesforce(organization_id, user_id=nil)
    salesforce_client_id = ENV['salesforce_client_id']
    salesforce_client_secret = ENV['salesforce_client_secret']
    hostURL = 'login.salesforce.com'
    # try to get salesforce production. if not connect, check if it is connected to salesforce sandbox
    if user_id
      salesforce_user = OauthUser.find_by(oauth_provider: 'salesforce', organization_id: organization_id, user_id: user_id)
    else
      salesforce_user = OauthUser.find_by(oauth_provider: 'salesforce', organization_id: organization_id)
    end

    if (salesforce_user.nil?)
      if user_id
        salesforce_user = OauthUser.find_by(oauth_provider: 'salesforcesandbox', organization_id: organization_id, user_id: user_id)
      else
        salesforce_user = OauthUser.find_by(oauth_provider: 'salesforcesandbox', organization_id: organization_id)
      end

      salesforce_client_id = ENV['salesforce_sandbox_client_id']
      salesforce_client_secret = ENV['salesforce_sandbox_client_secret']
      hostURL = 'test.salesforce.com' 
    end

    client = nil
    if(salesforce_user.present?)  
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
        puts "SalesforceService: Refreshing access token. Client established using Restforce gem.  Accessing user_info..."
        client.user_info
      rescue
        client = nil
        puts "*** SalesforceService error: Salesforce connection error! ***"
      end      
    end

    #return nil  # simulates a Salesforce connection error
    return client

  end

  def self.query_salesforce(client, query_statement)
    query_result = nil

    if (!client.nil?)
      begin
        query_result = client.query(query_statement)
      rescue  
        query_result = nil
        puts "*** SalesforceService error: Salesforce query error! Query: #{query_statement}"
      end     
    end

    #return nil  # simulates a Salesforce query error
    return query_result

  end

  # This is used to Insert CS activity into the corresponding SFDC account/opportunity
  # Parameters: sObject_meta - a hash that contains the :id (and :type, optional) of the SFDC sObject we are updating
  #             update_details - hash containing :activity_date, :subject, :priority, and :description of Salesforce Activity to write
  def self.update_salesforce(client, sObject_meta, update_details, update_type="ActivityHistory")
    update_result = nil
    
    if (!client.nil?)
      if update_type == "ActivityHistory"
        begin
          #TODO: Do an upsert instead of Delete followed by an Insert for performance
          #update_result = client.upsert('Task', nil, TaskSubtype: 'Task', Status: 'Completed', WhatId: sObject_meta[:id], ActivityDate: update_details[:activity_date], Subject: update_details[:subject], Priority: update_details[:priority], Description: update_details[:description])  # update_result is the new Task's Id
          #update_result = client.upsert('Task', 'Id', Id: newTask_Id, Subject: "New subject") if update_result.present?

          update_result = client.create('Task', TaskSubtype: 'Task', Status: 'Completed', WhatId: sObject_meta[:id], ActivityDate: update_details[:activity_date], Subject: update_details[:subject], Priority: update_details[:priority], Description: update_details[:description])  # update_result is the new Task's Id
          #puts "---> new Task creation=#{update_result}"
          if update_result == false
            puts "*** SalesforceService error: Salesforce update error while updating sObject_meta: #{sObject_meta}, sObject_fields: #{update_details} update_type: #{update_type}"
            update_result = nil
          end
        rescue  
          puts "*** SalesforceService error: Salesforce update error while updating sObject_meta: #{sObject_meta}, sObject_fields: #{update_details} update_type: #{update_type}"
          update_result = nil
        end    
      end 
    end

    #return nil  # simulates a Salesforce update error
    return update_result

  end
end