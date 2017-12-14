class SalesforceService

  # Returns a Salesforce connection client to be used to make Salesforce queries.
  # Parameter:  user - if obtaining an individual SFDC connection, specify the user requesting the connection; if the user is an admin, connection will be defaulted to the organization (admin) connection
  #             organization - to obtain the admin SFDC connection of an organization, specify the organization
  #             sfdc_oauthuser - (optional) the OauthUser record to use to attempt to connect to SFDC
  def self.connect_salesforce(user: nil, organization: nil, sfdc_oauthuser: nil)
    #return nil  # simulates a Salesforce connection error

    # Try to get salesforce production. If not connected, check if it is connected to SFDC sandbox
    sfdc_oauthuser = sfdc_oauthuser || SalesforceController.get_sfdc_oauthuser(user: (user if user.present?), organization: (organization if organization.present?))

    return nil if sfdc_oauthuser.blank?

    salesforce_client_id = (ENV['salesforce_client_id'] if sfdc_oauthuser.oauth_provider == 'salesforce') || ENV['salesforce_sandbox_client_id']
    salesforce_client_secret = (ENV['salesforce_client_secret'] if sfdc_oauthuser.oauth_provider == 'salesforce') || ENV['salesforce_sandbox_client_secret']
    hostURL = ('login.salesforce.com' if sfdc_oauthuser.oauth_provider == 'salesforce') || 'test.salesforce.com'

    client = nil
    # Restforce gem automatically refresh access token if expired       
    client = Restforce.new(host: hostURL,
                           client_id: salesforce_client_id,
                           client_secret: salesforce_client_secret,
                           oauth_token: sfdc_oauthuser.oauth_access_token,
                           refresh_token: sfdc_oauthuser.oauth_refresh_token,
                           authentication_callback: Proc.new { |x| puts x.to_s },
                           instance_url: sfdc_oauthuser.oauth_instance_url,
                           api_version: '38.0')
    begin
      puts "SalesforceService.connect_salesforce(): Refreshing access token. Client established using Restforce gem.  Accessing user_info... #{ client.user_info }"
    rescue => e
      if e.to_s == "invalid_grant: expired access/refresh token"
        puts "*** Informational message: SalesforceService cannot establish SFDC connection because access/refresh token for #{(user.email if user.present?) || organization.name} has expired! ***"
      else
        puts "*** SalesforceService error: Salesforce connection error has been detected.  Details: #{ e.to_s } ***"
      end
      return nil
    end
    begin
      puts "SalesforceService.connect_salesforce(): Daily SFDC API Requests Max/Limit=#{ client.limits["DailyApiRequests"][:Max] },  Requests remaining=#{ client.limits["DailyApiRequests"][:Remaining] }"
    rescue => e
      puts "*** Informational message: SalesforceService was unable to get Daily SFDC API Requests limits (#{ e.to_s }). However, the SFDC connection was successfully established! ***" if client.present?
    end

    client
  end

  # Returns the SFDC User (sObject) id of the SFDC connection belonging to a user+organization.
  # Parameters:   organization_id - uuid of the (CS) organization
  #               user_id - (optional) uuid of the (CS) user; if unspecified, this will return for the organization admin 
  def self.get_salesforce_user_uuid(organization_id, user_id=nil)
    # Try to get salesforce production
    salesforce_user = user_id ? OauthUser.find_by(oauth_provider: 'salesforce', organization_id: organization_id, user_id: user_id) : OauthUser.find_by(oauth_provider: 'salesforce', organization_id: organization_id)

    # If not connected, check if it is connected to SFDC sandbox
    if (salesforce_user.nil?)
      salesforce_user = user_id ? OauthUser.find_by(oauth_provider: 'salesforcesandbox', organization_id: organization_id, user_id: user_id) : OauthUser.find_by(oauth_provider: 'salesforcesandbox', organization_id: organization_id)
    end

    salesforce_user.oauth_provider_uid[salesforce_user.oauth_provider_uid.rindex(/\//)+1...salesforce_user.oauth_provider_uid.length] if salesforce_user.present?
  end

  # Returns the SFDC Organization (sObject) id of the SFDC connection belonging to an organization.
  # Parameters:   organization_id - uuid of the (CS) organization
  #               user_id - (optional) uuid of the (CS) user; if unspecified, this will return for the organization admin 
  def self.get_salesforce_organization_uuid(organization_id, user_id=nil)
    # Try to get salesforce production
    salesforce_user = user_id ? OauthUser.find_by(oauth_provider: 'salesforce', organization_id: organization_id, user_id: user_id) : OauthUser.find_by(oauth_provider: 'salesforce', organization_id: organization_id)

    # If not connected, check if it is connected to SFDC sandbox
    if (salesforce_user.nil?)
      salesforce_user = user_id ? OauthUser.find_by(oauth_provider: 'salesforcesandbox', organization_id: organization_id, user_id: user_id) : OauthUser.find_by(oauth_provider: 'salesforcesandbox', organization_id: organization_id)
    end

    (salesforce_user.oauth_provider_uid.match /(.+)\/(.+)\/(.+)/)[2] if salesforce_user.present?
  end

  # Parameters: client - connection to Salesforce
  #             query_statement - string statement to submit to SFDC
  # Returns:   A hash that represents the execution status/result of the query. Consists of:
  #             status - string "SUCCESS" if query successful; otherwise, "ERROR" 
  #             result - if status == "SUCCESS", contains the result of the query, otherwise, contains the title of the error
  #             detail - if status == "ERROR", contains the details of the error
  def self.query_salesforce(client, query_statement)
    result = nil

    # return { status: "ERROR", result: "SalesforceService error", detail: "Simulated SFDC query_salesforce error!" }  # simulate a Salesforce query error

    if (!client.nil?)
      begin
        query_result = client.query(query_statement)
        result = { status: "SUCCESS", result: query_result, detail: "" }
      rescue => e
        result = { status: "ERROR", result: "SalesforceService error", detail: "Salesforce query error: (#{ e.to_s }) Query: #{ query_statement }" }
        puts "*** SalesforceService error: Salesforce query error! (#{ e.to_s }) Query: #{query_statement}"
      end
    else
      result = { status: "ERROR", result: "SalesforceService error", detail: "Invalid Salesforce connection was passed to SalesforceService.query_salesforce." }
    end

    result
  end

  # This is used to export a single CS Salesforce account or opportunity back to Salesforce, or to export/create a single CS activity or a contact to the linked/mapped SFDC account/opportunity.
  # Parameters: client - connection to Salesforce
  #             params[:sObject_meta] - a hash that contains :id, a SFDC sObject uuid (and optionally :type, the SFDC sObject type the :id descries) that helps perform the update
  #             params[:update_type] - "account" to update (no create yet) a SFDC account with a CS salesforce_account,
  #                                    "opportunity" to update (no create yet) a SFDC opportunity with a CS salesforce_opportunity,
  #                                    "activity" to export CS activity to SFDC ActivityHistory, or
  #                                    "contact" to export CS contacts to SFDC Contacts
  #             params[:sObject_fields] - hash containing entity field values (for specific fields, see the individual types below)
  # Returns:   A hash that represents the execution status/result of the update. Consists of:
  #             status - "SUCCESS" if successful; otherwise, "ERROR" 
  #             result - sObject SFDC id that was created; otherwise, contains the title of the error
  #             detail - if status == "ERROR", contains the details of the error
  def self.update_salesforce(params)
    client = params[:client]
    result = nil
    # return { status: "ERROR", result: "Salesforce error", detail: "Just a simulated Salesforce error in SalesforceService.update_salesforce()" } # simulates a Salesforce query error

    # puts "\n\nparams[:sObject_fields]: #{params[:sObject_fields]}"
    if (!client.nil?)
      case (params[:update_type])
      when "account"
        begin
          acct_id = params[:sObject_meta][:id]
          update_result = nil
          params[:sObject_fields].each do |sfdc_field, new_val| 
            # TODO: Temporary hack until figure out how to convert string into parameter; which means, currently, we cannot export to any custom SFDC fields!
            case (sfdc_field)
            when "Name"
              update_result = client.update!('Account', Id: params[:sObject_meta][:id], Name: new_val)
            # TODO: Fix 'JSON_PARSER_ERROR: Cannot deserialize instance of BillingAddress from VALUE_STRING value' error on export!
            #when "BillingAddress"
              #update_result = client.update!('Account', Id: params[:sObject_meta][:id], BillingAddress: new_val)
            when "Description"
              update_result = client.update!('Account', Id: params[:sObject_meta][:id], Description: new_val)
            when "Phone"
              update_result = client.update!('Account', Id: params[:sObject_meta][:id], Phone: new_val)
            when "Website"
              update_result = client.update!('Account', Id: params[:sObject_meta][:id], Website: new_val)
            else
              puts "Cannot update field #{sfdc_field} -- No support for custom fields yet! :("
            end
          end
          result = { status: "SUCCESS", result: update_result, detail: "" }
        rescue => e
          detail = "Update Salesforce Account error. (#{ e.to_s }) sObject_meta: #{ params[:sObject_meta] }, sObject_fields: #{ params[:sObject_fields] }"
          puts "*** SalesforceService error: #{ detail }"
          result = { status: "ERROR", result: "SalesforceService error on update!", detail: detail }
        end
      when "opportunity"
        begin
          opp_id = params[:sObject_meta][:id]
          update_result = nil
          params[:sObject_fields].each do |sfdc_field, new_val|
            # TODO: Temporary hack until figure out how to convert string into parameter; which means, currently, we cannot export to any custom SFDC fields!
            case (sfdc_field)
            when "Name"
              update_result = client.update!('Opportunity', Id: opp_id, Name: new_val)
            when "CloseDate"
              update_result = client.update!('Opportunity', Id: opp_id, CloseDate: new_val.strftime("%Y-%m-%d"))
            when "Probability"
              update_result = client.update!('Opportunity', Id: opp_id, Probability: new_val)
            when "Amount"
              update_result = client.update!('Opportunity', Id: opp_id, Amount: new_val) 
            when "StageName"
              update_result = client.update!('Opportunity', Id: opp_id, StageName: new_val) 
            when "ForecastCategoryName"  
              update_result = client.update!('Opportunity', Id: opp_id, ForecastCategoryName: new_val) 
            else
              puts "Cannot update field #{sfdc_field} -- No support for custom fields yet! :("
            end
          end

          # params[:sObject_fields] = { name: ... , stage_name: ... , close_date: ... , probability: ... , amount: ... , forecast_category_name: ...  } ????

          result = { status: "SUCCESS", result: update_result, detail: "" }
        rescue => e
          detail = "Update Salesforce Opportunity error. (#{ e.to_s }) sObject_meta: #{ params[:sObject_meta] }, sObject_fields: #{ params[:sObject_fields] }"
          puts "*** SalesforceService error: #{ detail }"
          result = { status: "ERROR", result: "SalesforceService error on update!", detail: detail }
        end
      when "activity"
        begin
          # Insert CS activity into the corresponding SFDC account/opportunity.
          # Parameters: sObject_fields - hash containing :activity_date, :subject, :priority, and :description of Salesforce Activity to write
          #TODO: Do an upsert instead of Delete followed by an Insert for performance

          # update_result = client.upsert('Task', nil, TaskSubtype: 'Task', Status: 'Completed', WhatId: params[:sObject_meta][:id], ActivityDate: params[:sObject_fields][:activity_date], Subject: params[:sObject_fields][:subject], Priority: params[:sObject_fields][:priority], Description: params[:sObject_fields][:description])  # update_result is the new Task's Id
          # update_result = client.upsert('Task', 'Id', Id: newTask_Id, Subject: "New subject") if update_result.present?

          update_result = client.create!('Task', TaskSubtype: 'Task', Status: 'Completed', WhatId: params[:sObject_meta][:id], ActivityDate: params[:sObject_fields][:activity_date], Subject: params[:sObject_fields][:subject], Priority: params[:sObject_fields][:priority], Description: params[:sObject_fields][:description])  

          # return { status: "ERROR", result: "Salesforce error", detail: "This is just a simulated Salesforce error" }  # simulates a SFDC error

          # update_result is the new Task's sObject Id
          result = { status: "SUCCESS", result: update_result, detail: "" }
        rescue => e
          detail = "Update Salesforce Activity error while creating SFDC ActivityHistory. (#{ e.to_s }) sObject_meta: #{ params[:sObject_meta] }, sObject_fields: #{ params[:sObject_fields] }"
          puts "*** SalesforceService error: #{ detail }"
          result = { status: "ERROR", result: "SalesforceService error", detail: detail }
        end
      when "contact"
        # Export CS contacts into the corresponding SFDC account.
        # ).
        # If a contact is an existing Salesforce contact, then pass the sObject uuid of the Contact in params[:sObject_fields][:external_sfdc_id]. This will attempt to update the contact according to this SFDC id.  If creating a new Salesforce contact, omit params[:sObject_fields][:external_sfdc_id]. If the attempted update using SFDC external_source_id fails, this will make an attempt to upsert according to e-mail address (limit the search to the target SFDC Account).
        
        #puts ">>> params[external_sfdc_id]=#{ params[:external_sfdc_id] }" 
        #puts "Contact: #{ params[:sObject_fields][:FirstName] } #{ params[:sObject_fields][:LastName] } (external_sfdc_id: #{ params[:sObject_fields][:external_sfdc_id] })"

        if (params[:sObject_fields][:external_sfdc_id].present?) # contact is SFDC contact
          update_result = update_sfdc_contact(client: client, sfdc_contact_id: params[:sObject_fields][:external_sfdc_id], sfdc_account_id: params[:sObject_meta][:id], params: params[:sObject_fields])
        else
          update_result = upsert_sfdc_contact(client: client, sfdc_account_id: params[:sObject_meta][:id], contact: {Email: params[:sObject_fields][:Email], FirstName: params[:sObject_fields][:FirstName], LastName: params[:sObject_fields][:LastName]}, params: params[:sObject_fields])
        end
        # update_result[:result] contains the new Contact's sObject Id
        # update_result = { status: "ERROR", result: "Salesforce error", detail: "This is just a simulated Salesforce error" }  # simulated SFDC error

        if update_result[:status] == "SUCCESS"
          result = { status: "SUCCESS", result: update_result[:result], detail: update_result[:detail] }
        else
          detail = "Export Contacts to Salesforce error while creating/updating a SFDC Contact. sObject_meta: #{ params[:sObject_meta] }, sObject_fields: #{ params[:sObject_fields] } (#{ update_result[:detail] })"
          puts "*** SalesforceService error: #{ detail }"
          result = { status: "ERROR", result: "SalesforceService error", detail: detail }
        end
      else
        puts "*** ContextSmith error: Parameter params[:update_type] passed to SalesforceService.update_salesforce is invalid!  params[:update_type]=#{ params[:update_type] }"
        result = { status: "ERROR", result: "SalesforceService error", detail: "Parameter passed to an internal function is invalid." }
      end 
    else
      puts "** ContextSmith error: Parameter 'client' passed to SalesforceService.update_salesforce is invalid!"
      result = { status: "ERROR", result: "ContextSmith Error", detail: "Parameter passed to an internal function is invalid." }
    end

    result
  end

  private

  # Finds a Contact in SFDC Account that matches an e-mail address, or FirstName/LastName if no e-mail is specified or cannot be found.  If found, performs an update on the SFDC Contact.  If multiple Contacts are found, picks only one (first one alphabetically by LastName, then FirstName). If not found, a new SFDC Contact is created/inserted.  While exporting a non-existing (new) CS contact to SFDC, if last name doesn't exist for the contact, we will set the contact's e-mail address as the last name.  Returns nil if there is an error, or the Contact's SFDC/sObject id if successful.
  # Parameters:   client - connection to Salesforce
  #              sfdc_account_id - the SFDC/sObject id of the Salesforce Account to which to upsert the Contact
  #               contact  - a hash that contains Contact :Email, :FirstName, and :LastName (all strings) which is used to determine the contact to upsert
  #               params - a hash that contains the Contact information (e.g., FirstName, Email, etc.)
  # Returns:    A hash that represents the execution status/result of the upsert. Consists of:
  #               status - "SUCCESS" if successful, or "ERROR" otherwise
  #               result - if status == "SUCCESS", contains the sObject Id of Contact created; otherwise, contains the title of the error
  #               detail - if status == "ERROR", contains the details of the error; if a duplicate contact was detected during create SFDC Contact, a warning is here warning user that Contacts may not be properly copied because a "Contact Duplicate Rule" in SFDC settings might be preventing us from creating new SFDC Contacts. This will contain a message stating if the retry was successful or failed, and if we retried the upsert (i.e., using only the Contact's Email field.)

  # TODO: Use SFDC duplicates warning to tell user "If Contacts are incorrectly flagged as duplicates, you may need your Salesforce Administrator to modify/deactivate your \”Contact Duplicate Rules\” in Salesforce Setup."
  # TODO: Possible optimization is retain a temporary list of all contacts in an account, per request and to be discarded after the request, for use of determining if a contact currently exists (and what the LastModifiedDate date is for this contact) to avoid individual querying to determine the same. 
  def self.upsert_sfdc_contact(client: , sfdc_account_id: , contact: , params: )
    result = nil

    # Attempt to match by E-mail
    query_statement = "SELECT Id, AccountId, FirstName, LastName, Email, Title, Department, Phone, MobilePhone FROM Contact WHERE AccountId='#{sfdc_account_id}' AND Email='#{ return_escaped_SFDC_field_val(contact[:Email]) }' ORDER BY LastName, FirstName"  # Unused: Description    
    # puts "query_statement: #{ query_statement }"
    query_result = self.query_salesforce(client, query_statement)

    if query_result[:status] == "ERROR"
      detail = "Export Contacts to Salesforce error while querying SFDC. (#{ query_result[:detail] }) \"Standard\" SFDC columns were used, but query may still fail if not all columns are set up on Salesforce!  Check query on SFDC Developer console or check Contact fields on Salesforce.com.  query_statement: #{ query_statement }, sObject_meta: #{ params }, sObject_fields: #{ params[:sObject_fields] }"
      puts "*** SalesforceService error: #{ detail }"
      return { status: "ERROR", result: "SalesforceService error", detail: detail }
    end

    # If cannot match by E-mail, try matching by First/Last name if either are specified
    if query_result[:result].size == 0 && (contact[:FirstName].strip.present? || contact[:LastName].strip.present?)
      puts "*> Cannot match Contact by E-mail, trying to match by First/Last name instead!"
      contact_name_predicate = []
      contact_name_predicate << "FirstName='#{ return_escaped_SFDC_field_val(contact[:FirstName].strip) }'" if contact[:FirstName].strip.present?
      contact_name_predicate << "LastName='#{ return_escaped_SFDC_field_val(contact[:LastName].strip) }'" if contact[:LastName].strip.present?

      query_statement = "SELECT Id, AccountId, FirstName, LastName, Email, Title, Department, Phone, MobilePhone FROM Contact WHERE AccountId='#{sfdc_account_id}' AND (#{ contact_name_predicate.join(" AND ") }) ORDER BY LastName, FirstName"  # Unused: Description    
      # puts "query_statement: #{ query_statement }"
      query_result = self.query_salesforce(client, query_statement)

      if query_result[:status] == "ERROR"
        detail = "Export Contacts to Salesforce error while querying SFDC. (#{ query_result[:detail] }) \"Standard\" SFDC columns were used, but query may still fail if not all columns are set up on Salesforce!  Check query on SFDC Developer console or check Contact fields on Salesforce.com.  query_statement: #{ query_statement }, sObject_meta: #{ params }, sObject_fields: #{ params[:sObject_fields] }"
        puts "*** SalesforceService error: #{ detail }"
        return { status: "ERROR", result: "SalesforceService error", detail: detail }
      end
    end

    unless query_result[:result].size == 0   
      c = query_result[:result].first  # pick one matched Contact, in case of multiple matches
      # puts "==> Matched the following SFDC contact:  Email=#{c[:Email]} FirstName=#{c[:FirstName]} LastName=#{c[:LastName]}"
      upsert_result = update_sfdc_contact(client: client, sfdc_contact_id: c[:Id], sfdc_account_id: sfdc_account_id, params: params)
      if upsert_result[:status] == "SUCCESS"
        result = { status: "SUCCESS", result: upsert_result[:result], detail: "" }
      else
        result = { status: "ERROR", result: "SalesforceService error", detail: upsert_result[:detail] }
      end
    else
      begin
        puts "--> Contact #{ contact[:Email] } in SFDC Account '#{ sfdc_account_id }' not found. Creating a new Contact..."
        upsert_result = client.create!('Contact', AccountId: sfdc_account_id, FirstName: params[:FirstName], LastName: params[:LastName].present? ? params[:LastName] : contact[:Email], Email: contact[:Email], Title: params[:Title], Department: params[:Department], Phone: params[:Phone], MobilePhone: params[:MobilePhone])  # Unused: LeadSource: params[:LeadSource].blank? ? "ContextSmith" : params[:LeadSource], Description: params[:Description]
        # upsert_result is the Contact's SFDC sObject Id
        result = { status: "SUCCESS", result: upsert_result, detail: "" }
      rescue => e
        if (e.to_s[0...19]) == "DUPLICATES_DETECTED" 
          detail = "Export Contacts to Salesforce error -- DUPLICATE contact detected -- while creating SFDC Contact! If Contacts are incorrectly flagged as duplicates, you may need your Salesforce Administrator to modify/deactivate your \"Contact Duplicate Rules\" in Salesforce Setup.  Attempting to create Contact with only the minimal fields: Email ... "
          begin
            # Attempt to create Contact with only minimal Contact fields
            upsert_result = client.create!('Contact', AccountId: sfdc_account_id, FirstName: '', LastName: contact[:Email], Email: contact[:Email]) # Unused: LeadSource: params[:LeadSource].blank? ? "ContextSmith" : params[:LeadSource]
            detail += "Contact successfully created."
            puts "*** SalesforceService warning: #{ detail }"
            result = { status: "SUCCESS", result: upsert_result, detail: detail }
          rescue => e2
            detail += "Error creating contact! (#{ e2.to_s })"
            puts "*** SalesforceService error: #{ detail }"
            result = { status: "ERROR", result: "SalesforceService error", detail: detail }
          end
        else # all other errors
          detail = "Export Contacts to Salesforce error while creating a new SFDC Contact. (#{ e.to_s }). sObject_meta: #{ params[:sObject_meta] }, sObject_fields: #{ params[:sObject_fields] }"
          puts "*** SalesforceService error: upsert_sfdc_contact #{ detail }"
          result = { status: "ERROR", result: "SalesforceService error", detail: detail }
        end
      end
    end

    result
  end

  # Updates a Salesforce Contact with Id = sfdc_contact_id with Contact info in params. If the SFDC sfdc_contact_id cannot be found, try to find it using Contact's e-mail in the SFDC Account. SFDC Contact field will only be updated if there is a value in the corresponding CS field.
  # Parameters (all required):  client - connection to Salesforce
  #                             sfdc_contact_id - (required) the external sObject id that identifies the Salesforce Contact to update
  #                             sfdc_account_id - the SFDC/sObject id of the Salesforce Account where the Contact resides
  #                             params - a hash that contains the Contact information (e.g., FirstName, LastName, Email, etc.)
  # Returns:   A hash that represents the execution status/result of the update. Consists of:
  #             status - "SUCCESS" if successful, or "ERROR" otherwise
  #             result - if status == "SUCCESS", contains the sObject Id of Contact created; otherwise, contains the title of the error
  #             detail - if status == "ERROR", contains the details of the error; if a sfdc_contact_id was invalid, and the retry using upsert is successful, this will contain a message stating an upsert was performed instead and was successful.
  def self.update_sfdc_contact(client: , sfdc_contact_id: , sfdc_account_id: , params: )
    result = nil
    begin
      client.update!('Contact', Id: sfdc_contact_id, FirstName: params[:FirstName]) if params[:FirstName].present?
      client.update!('Contact', Id: sfdc_contact_id, LastName: params[:LastName]) if params[:LastName].present?
      client.update!('Contact', Id: sfdc_contact_id, Email: params[:Email]) if params[:Email].present?
      client.update!('Contact', Id: sfdc_contact_id, Title: params[:Title]) if params[:Title].present?
      client.update!('Contact', Id: sfdc_contact_id, Department: params[:Department]) if params[:Department].present?
      client.update!('Contact', Id: sfdc_contact_id, Phone: params[:Phone]) if params[:Phone].present?
      client.update!('Contact', Id: sfdc_contact_id, MobilePhone: params[:MobilePhone]) if params[:MobilePhone].present?
      # client.update!('Contact', Id: sfdc_contact_id, Description: params[:Description]) if params[:Description].present?
      # update_result = client.update!('Contact', Id: sfdc_contact_id, xxxxxx: params[:xxxxxx]) if params[:xxxxxx].present?
      result = { status: "SUCCESS", result: sfdc_contact_id, detail: "" }
    rescue => e
      # puts "\n\n\n\t\t<><> We're now in the 'error recovery' update_sfdc_contact path: re-try using upsert_sfdc_contact! <><>\n\n\n"
      detail = ""
      if (e.to_s[0...9]) == "NOT_FOUND" || (e.to_s[0...17]) == "ENTITY_IS_DELETED" || (e.to_s[0...27]) == "INVALID_CROSS_REFERENCE_KEY" # SFDC Contact was deleted on Salesforce (invalidating the Id saved in app) or the external SFDC Id of Contact is corrupted/invalid
      #(e.to_s[0...25]) == "FIELD_INTEGRITY_EXCEPTION"   # Is this obsolete??

        detail += "Export Contacts to Salesforce error -- invalid salesforce Contact Id specified while updating SFDC Contact! (#{ e.to_s }) Attemping to upsert Contact using e-mail/FirstName/LastName instead. "
        upsert_result = upsert_sfdc_contact(client: client, sfdc_account_id: sfdc_account_id, contact: {Email: params[:Email], FirstName: params[:FirstName], LastName: params[:LastName]}, params: params)
        if upsert_result[:status] == "SUCCESS"
          detail += "Contact successfully upserted!"
          puts "*** SalesforceService warning: #{ detail }"
          return { status: "SUCCESS", result: upsert_result[:result], detail: detail }
        else
          detail += "Contact failed upsert. (#{ upsert_result[:detail] }) "
        end
      elsif (e.to_s[0...19]) == "DUPLICATES_DETECTED"
        detail += "Export Contacts to Salesforce error -- DUPLICATE contact detected -- while updating SFDC Contact! If Contacts are incorrectly flagged as duplicates, you may need your Salesforce Administrator to modify/deactivate your \"Contact Duplicate Rules\" in Salesforce Setup. Contact skipped! "
      else
        detail += "Export Contacts to Salesforce error while updating a SFDC Contact: (#{ e.to_s }) "
      end
      detail += "sObject_meta: #{ params[:sObject_meta] }, sObject_fields: #{ params[:sObject_fields] }"
      puts "*** SalesforceService error: #{ detail }"
      result = { status: "ERROR", result: "SalesforceService error", detail: detail }
    end # end: rescue

    #puts ">>> result: #{result}"
    result
  end

  # Changes 'val' to a valid value to be used in a SFDC SOQL query. e.g., escapes single quotes
  def self.return_escaped_SFDC_field_val(val)
    if val.present?
      val.gsub("'", "\\\\'") 
    else
      val
    end
  end
end