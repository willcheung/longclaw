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
        puts "SalesforceService.connect_salesforce(): Refreshing access token. Client established using Restforce gem.  Accessing user_info... #{ client.user_info }"
      rescue => e
        puts "*** SalesforceService error: Salesforce connection error!  Details: #{ e.to_s } ***"
        client = nil
      end
      begin
        puts "SalesforceService.connect_salesforce(): Daily SFDC API Requests Max/Limit=#{ client.limits["DailyApiRequests"][:Max] },  Requests remaining=#{ client.limits["DailyApiRequests"][:Remaining] }"
      rescue => e
        puts "Informational message: SalesforceService was unable to get Daily SFDC API Requests limits (#{ e.to_s }). However, the SFDC connection was successfully established!"
      end
    end

    #return nil  # simulates a Salesforce connection error
    return client
  end

  # Parameters: client - connection to Salesforce
  #             query_statement - string statement to submit to SFDC
  def self.query_salesforce(client, query_statement)
    query_result = nil

    if (!client.nil?)
      begin
        query_result = client.query(query_statement)
      rescue => e
        query_result = nil
        puts "*** SalesforceService error: Salesforce query error! (#{ e.to_s }) Query: #{query_statement}"
      end     
    end

    #return nil  # simulates a Salesforce query error
    return query_result
  end

  # This is used to export/create CS activity or contacts to the linked/mapped SFDC account/opportunity.  If succesful, returns the sObject SFDC id that was created; otherwise, returns nil for failures.
  # Parameters: client - connection to Salesforce
  #             params[:sObject_meta] - a hash that contains the :id (and :type, optional) of the SFDC sObject we are updating
  #             params[:update_type] - "activity" to export activity to SFDC ActivityHistory, "contacts" to export contacts to SFDC Contacts
  #             params[:sObject_fields] - hash containing entity field values (for specific fields, see the individual types below)
  def self.update_salesforce(params)
    client = params[:client]
    update_result = nil

    if (!client.nil?)
      case (params[:update_type])
      when "activity"
        begin
          # Insert CS activity into the corresponding SFDC account/opportunity.
          # Parameters: sObject_fields - hash containing :activity_date, :subject, :priority, and :description of Salesforce Activity to write
          #TODO: Do an upsert instead of Delete followed by an Insert for performance

          # update_result = client.upsert('Task', nil, TaskSubtype: 'Task', Status: 'Completed', WhatId: params[:sObject_meta][:id], ActivityDate: params[:sObject_fields][:activity_date], Subject: params[:sObject_fields][:subject], Priority: params[:sObject_fields][:priority], Description: params[:sObject_fields][:description])  # update_result is the new Task's Id
          # update_result = client.upsert('Task', 'Id', Id: newTask_Id, Subject: "New subject") if update_result.present?

          update_result = client.create('Task', TaskSubtype: 'Task', Status: 'Completed', WhatId: params[:sObject_meta][:id], ActivityDate: params[:sObject_fields][:activity_date], Subject: params[:sObject_fields][:subject], Priority: params[:sObject_fields][:priority], Description: params[:sObject_fields][:description])  
          # update_result is the new Task's sObject Id
          #puts "---> new Task creation result = \"#{update_result}\""
          if update_result == false
            puts "*** SalesforceService error: Update Salesforce Activity error while creating SFDC ActivityHistory. sObject_meta: #{ params[:sObject_meta] }, sObject_fields: #{ params[:sObject_fields] }"
            update_result = nil
          end
        rescue  
          puts "*** SalesforceService error: Update Salesforce Activity error while creating SFDC ActivityHistory. sObject_meta: #{ params[:sObject_meta] }, sObject_fields: #{ params[:sObject_fields] }"
          update_result = nil
        end
      when "contacts"
        # Export CS contacts into the corresponding SFDC account.
        # Note: If a contact is determined to be a Salesforce contact, make an attempt to update the contact according to SFDC external_source_id.  If not a Salesforce contact (or update using SFDC external_source_id fails), make an attempt to upsert according to e-mail address (limit the search to the target SFDC Account).
        
        #puts ">>> params[external_sfdc_id]=#{ params[:external_sfdc_id] }" 
        #puts "Contact: #{ params[:sObject_fields][:FirstName] } #{ params[:sObject_fields][:LastName] } (external_sfdc_id: #{ params[:sObject_fields][:external_sfdc_id] })"
        if (params[:sObject_fields][:external_sfdc_id].present?)
          update_result = update_sfdc_contact(client: client, sfdc_contact_id: params[:sObject_fields][:external_sfdc_id], sfdc_account_id: params[:sObject_meta][:id], params: params[:sObject_fields])
        else
          update_result = self.upsert_sfdc_contact(client: client, sfdc_account_id: params[:sObject_meta][:id], email: params[:sObject_fields][:Email], params: params[:sObject_fields])
        end
        # update_result is the new Contact's sObject Id ?
        if update_result == false
          puts "*** SalesforceService error: Export Contacts to Salesforce error while creating/updating a SFDC Contact. sObject_meta: #{ params[:sObject_meta] }, sObject_fields: #{ params[:sObject_fields] }"
          update_result = nil
        end
      else
        return nil # Wrong parameter passed
      end 
    end

    #return nil  # simulates a Salesforce update error
    return update_result
  end

  private

  # Finds a Contact in SFDC Account that matches an e-mail address.  If found, performs an update on the SFDC Contact.  If multiple Contacts are found, picks only one (first one alphabetically by last name). If not found, a new SFDC Contact is created/inserted.  Returns nil if there is an error, or the Contact's SFDC/sObject id if successful.
  # Parameters:  client - connection to Salesforce
  #              sfdc_account_id - the SFDC/sObject id of the Salesforce Account to which to upsert the Contact
  #              email  - string, the email to search for to determine the contact to upsert
  #              params - a hash that contains the Contact information (e.g., FirstName, Email, etc.)
  # TODO: Warn user that Contacts may not be properly copied because a "Contact Duplicate Rules" in SFDC settings might be preventing this method from creating new contacts. e.g., "If Contacts are incorrectly flagged as duplicates, you may need your Salesforce Administrator to modify/deactivate your \”Contact Duplicate Rules\” in Salesforce Setup."
  def self.upsert_sfdc_contact(client: , sfdc_account_id: , email: , params: )
    query_statement = "SELECT Id, AccountId, FirstName, LastName, Email, Title, Department, Phone, MobilePhone FROM Contact WHERE AccountId='#{sfdc_account_id}' AND Email='#{email}' ORDER BY LastName, FirstName"  # Unused: Description
    
    query_result = self.query_salesforce(client, query_statement)

    if query_result.nil?
      puts "*** SalesforceService error: Export Contacts to Salesforce error while querying SFDC. Standard SFDC columns were used, but query will still fail if somehow not all columns were set up on Salesforce!  Check query on SFDC Developer console or check Contact fields on Salesforce.com.  query_statement: #{ query_statement }, sObject_meta: #{ params }, sObject_fields: #{ params[:sObject_fields] }"
      return nil  # propogate error to caller
    end

    unless query_result.size == 0   
      c = query_result.first  # pick one matched Contact
      upsert_result = update_sfdc_contact(client: client, sfdc_contact_id: c[:Id], sfdc_account_id: sfdc_account_id, params: params)
    else
      begin
        puts "Contact #{ email } in SFDC Account #{ sfdc_account_id } not found. Creating a new Contact..."
        #puts "...with params: #{params}"
        upsert_result = client.create!('Contact', AccountId: sfdc_account_id, FirstName: params[:FirstName], LastName: params[:LastName], Email: params[:Email], Title: params[:Title], Department: params[:Department], Phone: params[:Phone], MobilePhone: params[:MobilePhone])  # Unused: LeadSource: params[:LeadSource].blank? ? "ContextSmith" : params[:LeadSource], Description: params[:Description]
        if upsert_result == false
          puts "*** SalesforceService error: Export Contacts to Salesforce error while creating a new SFDC Contact. sObject_meta: #{ params }, sObject_fields: #{params[:sObject_fields]}"
          upsert_result = nil
        end
      rescue => e
        if (e.to_s[0...19]) == "DUPLICATES_DETECTED" 
          print "*** SalesforceService error: Export Contacts to Salesforce error -- DUPLICATE contact detected -- while creating SFDC Contact! If Contacts are incorrectly flagged as duplicates, you may need your Salesforce Administrator to modify/deactivate your \"Contact Duplicate Rules\" in Salesforce Setup.  Attempting to create Contact with only minimal Contact fields: FirstName, LastName, and Email ... "
          upsert_result = client.create('Contact', AccountId: sfdc_account_id, FirstName: params[:FirstName], LastName: params[:LastName], Email: params[:Email]) # Unused: LeadSource: params[:LeadSource].blank? ? "ContextSmith" : params[:LeadSource]
          puts "Contact successfully created!"
          return upsert_result  #return "N/A (duplicate contact; skipped!)"
        else
          puts "*** SalesforceService error: Export Contacts to Salesforce error while creating a new SFDC Contact. (#{ e.to_s }). sObject_meta: #{ params[:sObject_meta] }, sObject_fields: #{ params[:sObject_fields] }" 
        end
        upsert_result = nil
      end
    end

    upsert_result # nil (error), or the Contact's sObject Id
  end

  # Updates the Salesforce Contact with info in params. If the SFDC sfdc_contact_id cannot be found, try to find it using Contact's email in the SFDC Account
  # Parameters (all required):  client - connection to Salesforce
  #                             sfdc_contact_id - the external sObject id that identifies the Salesforce Contact to update
  #                             sfdc_account_id - the SFDC/sObject id of the Salesforce Account where the Contact resides
  #                             params - a hash that contains the Contact information (e.g., FirstName, LastName, Email, etc.)
  def self.update_sfdc_contact(client: , sfdc_contact_id: , sfdc_account_id: , params: )
    begin
      update_result = client.update!('Contact', Id: sfdc_contact_id, FirstName: params[:FirstName], LastName: params[:LastName], Title: params[:Title], Department: params[:Department], Phone: params[:Phone], MobilePhone: params[:MobilePhone])  # Unused:  Description: params[:Description]
      update_result = sfdc_contact_id
    rescue => e
      error = "*** SalesforceService error: "
      if (e.to_s[0...25]) == "FIELD_INTEGRITY_EXCEPTION" # In case SFDC Contact was deleted on Salesforce, or external SFDC Id of Contact is invalid
        puts error + "Export Contacts to Salesforce error -- invalid salesforce Contact Id -- while updating SFDC Contact! (#{ e.to_s })  Will attempt to upsert Contact using e-mail instead."
        return upsert_sfdc_contact(client: client, sfdc_account_id: sfdc_account_id, email: params[:Email], params: params)
      # elsif (e.to_s[0...19]) == "DUPLICATES_DETECTED" 
      #   error += "Export Contacts to Salesforce error -- DUPLICATE contact detected -- while updating SFDC Contact! Contact skipped."
      #   update_result = "N/A (duplicate contact; skipped!)"
      else
        error += "Export Contacts to Salesforce error while updating a SFDC Contact: (#{ e.to_s }) 
        update_result = nil
      end
      error += "sObject_meta: #{ params[:sObject_meta] }, sObject_fields: #{ params[:sObject_fields] }"
      puts error
      return update_result
    end

    update_result # nil (error), or the Contact's sObject Id
  end

  # Call this from ProjectsController#refresh !!
  # Parameters: project - the CS stream that we will attempt to refresh from SFDC
  #             query?
  def self.load_activity_from_salesforce(project, query=nil, save_in_db=true, after=nil, is_time=true, request=true, is_test=false)
    client = self.connect_salesforce(current_user.organization_id)
    # Find the SFDC opportunities/accounts mapped to project
    # Then call Activity.load_salesforce_activities(client, project, sfdc_id, type="Account", filter_predicates=nil
  end
end