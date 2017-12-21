class SalesforceController < ApplicationController
  layout "empty", only: :index
  before_action :get_current_org_users, only: :index

  ERRORS = { SalesforceConnectionError: "SalesforceConnectionError" }

  # For accessing Project#show page+tabs from a Salesforce Visualforce iframe page
  # The route is in the form GET http(s)://<host_url>/salesforce/?id=<salesforce_account_id>&pid=<contextsmith_project_id> ("&pid" and &actiontype=" is optional) , e.g. "https://app.contextsmith.com/salesforce?id=0014100000A88VlPVL"
  def index
    @category_param = []
    @filter_email = []

    @id_param_present = false
    @is_mapped_to_CS_account = false

    if params[:id].nil?
      return
    else
      @id_param_present = true
      # Set this salesforce id to contextsmith account id and then try to find a SF account mapping
      @salesforce_id = params[:id]  
      sfdc_account = SalesforceAccount.eager_load(:account).find_by(salesforce_account_id: @salesforce_id, contextsmith_organization_id: current_user.organization_id)
      return if sfdc_account.nil?  # invalid SFDC id or id cannot be found

      cs_account = sfdc_account.account
      return if cs_account.nil?  # no CS accounts mapped to this Salesforce account
    end

    @is_mapped_to_CS_account = true

    @actiontype = (params[:actiontype].present? && (["index", "show", "filter_timeline", "more_timeline", "tasks_tab", "insights_tab", "arg_tab"].include? params[:actiontype])) ? params[:actiontype] : 'show'

    # check if CS account_id is valid and in the scope
    @opportunities_mapped = Project.visible_to(current_user.organization_id, current_user.id).where(account_id: cs_account.id)
    #@opportunities_mapped.each { |p| puts "**************** project=#{ p.name }"}
    #puts ">>>>>>>>>>>>>>>>>>>>>>>>>>> cs_account.id=#{cs_account.id}"

    activities = []
    if @opportunities_mapped.present?
      if params[:pid].present?
        @project = @opportunities_mapped.detect {|p| p.id == params[:pid]} || nil
      else
        @project = @opportunities_mapped[0]
      end

      return if @project.blank?
      #puts ">>>>>>>>>>>> @project = #{@project.id}, #{@project.name}" 

      # Top status
      @project_open_tasks_count = @project.notifications.open.count

      # Tab specific (directly copied from "projects_controller.rb")
      get_show_data
      load_timeline if ["show", "filter_timeline", "more_timeline"].include? @actiontype

      if @actiontype == "show"
        # get data for user filter
        @final_filter_user = @project.all_involved_people(current_user.email)
        # get data for time series filter
        @activities_by_category_date = @project.daily_activities(current_user.time_zone).group_by { |a| a.category }
        @pinned_activities = @project.activities.pinned.visible_to(current_user.email).reverse
        # get categories for category filter
        @categories = @activities_by_category_date.keys
        @categories << Activity::CATEGORY[:Pinned] if @pinned_activities.present?
      elsif @actiontype == "tasks_tab"
        # show every risk regardless of private conversation
        @notifications = @project.notifications
      elsif @actiontype == "arg_tab" # Account Relationship Graph
        @data = @project.activities.where(category: %w(Conversation Meeting)).ids
        @contacts = @project.contact_relationship_metrics
      end
    end

    if(!params[:category].nil? and !params[:category].empty?)
      @category_param = params[:category].split(',')
    end

    if(!params[:emails].nil? and !params[:emails].empty?)
      @filter_email = params[:emails].split(',')
    end
  end

  # Returns a Salesforce OauthUser object for either a user or an organization suitable to be used to be used by SalesforceService.connect_salesforce.  If a user is specified and the user is not an Admin, this will return the SFDC OauthUser object for an individual login.  If an organization is specified, or if a user with Admin role is passed, then use the login belonging to the "organization".  
  # Note: If neither user nor organization was provided, or if OauthUser object cannot be found, returns nil.
  def self.get_sfdc_oauthuser(user: nil, organization: nil)
    if (user.present? && user.admin?) || (organization.present?)
      # Admin connection
      # Try to find SFDC production, then try SFDC sandbox.
      sfdc_oauthuser = OauthUser.find_by(oauth_provider: 'salesforce', organization_id: (user.organization_id if user.present?) || organization.id, user_id: nil) || OauthUser.find_by(oauth_provider: 'salesforcesandbox', organization_id: (user.organization_id if user.present?) || organization.id, user_id: nil)
    elsif user.present?
      # Individual (e.g., power user) connection
      sfdc_oauthuser = OauthUser.find_by(oauth_provider: 'salesforce', organization_id: user.organization_id, user_id: user.id) || OauthUser.find_by(oauth_provider: 'salesforcesandbox', organization_id: user.organization_id, user_id: user.id)
    end

    sfdc_oauthuser
  end

  # Load SFDC Accounts and new SFDC Opportunities and update values in mapped (standard and custom) fields.  For linked CS accts, if import SFDC contacts is enabled, then import SFDC contacts into CS.  For linked CS opps, if import/export SFDC activities is enabled and this is running for a periodic refresh task (e.g., "daily refresh"), then sychronize (import/export) SFDC and CS activities.
  # For individual (non-admin, e.g., "Pro") users: create CS opportunities and corresponding accts for open and unlinked SFDC opps owned by user, link the CS Acct and Opps to the corresponding SFDC entity, and create account Contacts.
  # Parameters:     client - a valid SFDC connection
  #                 user - the user making the request, admin or individual (non-admin)
  #                 for_periodic_refresh - true, import contacts and import/export activities that were updated since the last contacts or activities import/export (by timestamps found in CustomConfiguration, respectively); otherwise, false (default), import all contacts but syncs NO activities
  def self.import_and_create_contextsmith(client: , user: , for_periodic_refresh: false)
    method_name = "SalesforceController.import_and_create_contextsmith"
    # Upsert SFDC Accounts and SFDC Opportunities
    SalesforceAccount.load_accounts(client, user.organization_id) 
    if user.admin?
      SalesforceOpportunity.load_opportunities(client: client, organization: user.organization)
    else
      SalesforceOpportunity.load_opportunities(client: client, user: user)
    end

    # For non-Admin users, create CS Accounts and Opportunities and link them
    if !user.admin?
      sfdc_userid = SalesforceService.get_salesforce_user_uuid(user.organization_id, user.id)
      open_sfdc_opps = SalesforceOpportunity.is_open.is_not_linked.where(owner_id: sfdc_userid) #salesforce_account_id, salesforce_opportunity_id, name

      open_sfdc_opps_acct_ids = open_sfdc_opps.map(&:salesforce_account_id).uniq
      open_sfdc_opps_acct_ids.each do |acct_id|
        # Find the linked CS account, or create a corresponding CS account, for each SFDC account that is the parent of an open SFDC opportunity; if a new CS account was created, link the CS and SFDC accounts
        sfa = user.organization.salesforce_accounts.find_by_salesforce_account_id(acct_id)
        if sfa.present? && sfa.contextsmith_account_id.present? # SFDC account is linked
          account = user.organization.accounts.find(sfa.contextsmith_account_id) 
        else # SFDC account is not linked
          account = Account.new(domain: '', # like a custom account
                      name: sfa.salesforce_account_name.strip, 
                      owner_id: user.id, 
                      organization_id: user.organization_id,
                      description: "Automatically imported from Salesforce by ContextSmith",
                      created_by: user.id,
                      updated_by: user.id
                      )
          if account.save(validate: false)
            sfa.contextsmith_account_id = account.id
            sfa.save
          else
            puts "Error creating CS Account '#{sfa.salesforce_account_name}'!"
          end
        end
        # Find each unlinked SFDC opportunity, create a new CS opportunity under the appropriate CS account; if a new CS opportunity was created, link the CS and SFDC opportunities
        open_sfdc_opps.where(salesforce_account_id: sfa.salesforce_account_id).each do |sfo|
          if sfo.contextsmith_project_id.blank?  # SFDC opportunity is not linked
            project = user.organization.projects.new(name: sfo.name,
                        status: "Active",
                        owner_id: user.id,
                        account_id: account.id,
                        # is_public: true,
                        # is_confirmed: false 
                        created_by: user.id,
                        updated_by: user.id
                        )
            if project.save
              sfo.contextsmith_project_id = project.id
              sfo.save
            else
              puts "Error creating CS Opportunity '#{sfo.name}'!"
            end
          end
        end
      end # end: open_sfdc_opps_acct_ids.each do |acct_id|
    end # end: if !user.admin?

    # Import/update the standard and custom field values of mapped accts and opps
    SalesforceAccount.refresh_fields(client, user)
    SalesforceOpportunity.refresh_fields(client, user)

    # Import/upsert contacts into all linked accts (from SFDC into ContextSmith) if contacts import is enabled?
    sfdc_oauthuser = SalesforceController.get_sfdc_oauthuser(user: user)
    if sfdc_oauthuser.present? && sfdc_oauthuser.user_id.blank? 
      # organization
      import_contacts_sfdc_refresh_config = CustomConfiguration.salesforce_sync.where("((config_value::jsonb)->>'contacts')::jsonb ?| array[:keys] AND user_id IS NULL", keys: ['import']).find_by(organization_id: user.organization_id)
    else
      # individual
      import_contacts_sfdc_refresh_config = CustomConfiguration.salesforce_sync.where("((config_value::jsonb)->>'contacts')::jsonb ?| array[:keys]", keys: ['import']).find_by(organization_id: user.organization_id, user_id: user.id)
    end

    if import_contacts_sfdc_refresh_config.present?  # import SFDC contacts is enabled
      # if available, use CustomConfiguration last contacts refresh timestamp
      prev_import_ts = DateTime.parse(import_contacts_sfdc_refresh_config.config_value['contacts']['import']).utc if import_contacts_sfdc_refresh_config.config_value['contacts']['import'].present?
      error_occurred = false
      new_import_ts = Time.now.utc

      user.organization.salesforce_accounts.is_linked.each do |sfa|
        account = sfa.account
        if for_periodic_refresh && prev_import_ts.present? # run during a periodic refresh + prev import contacts timestamp present
          import_result = Contact.load_salesforce_contacts(client, account.id, sfa.salesforce_account_id, prev_import_ts, new_import_ts)
        else
          import_result = Contact.load_salesforce_contacts(client, account.id, sfa.salesforce_account_id, nil, new_import_ts)
        end

        if import_result[:status] == "ERROR"
          puts "****SFDC**** Error at Contact.load_salesforce_contacts() in #{method_name} during import of contacts from Salesforce Account \"#{sfa.salesforce_account_name}\" (sfdc_id='#{sfa.salesforce_account_id}') to CS Account \"#{account.name}\" (account_id='#{account.id}').  #{ import_result[:result] } Details: #{ import_result[:detail] }"
          error_occurred = true
        end
      end if user.organization.salesforce_accounts.present? # End: user.organization.salesforce_accounts.is_linked.each do |sfa|

      unless error_occurred
        # puts "****SFDC**** Automatic import of SFDC contacts for user_id=#{user.id} of organization_id=#{user.organization_id} was successful."
        import_contacts_sfdc_refresh_config.config_value['contacts']['import'] = new_import_ts
        import_contacts_sfdc_refresh_config.save
      end
    end # End: if import SFDC contacts is enabled

    # Import/export activities into all linked opportunities (from SFDC into ContextSmith / from CS out to SFDC) if import/export SFDC activities is enabled
    if sfdc_oauthuser.present? && sfdc_oauthuser.user_id.blank? 
      # organization
      sync_sfdc_act_config = CustomConfiguration.salesforce_sync.where("((config_value::jsonb)->>'activities')::jsonb ?| array[:keys] AND user_id IS NULL", keys: ['import','export']).find_by(organization_id: user.organization_id)
    else
      # individual
      sync_sfdc_act_config = CustomConfiguration.salesforce_sync.where("((config_value::jsonb)->>'activities')::jsonb ?| array[:keys]", keys: ['import','export']).find_by(organization_id: user.organization_id, user_id: user.id)
    end

    if for_periodic_refresh && sync_sfdc_act_config.present?  # run during a periodic refresh + import OR export SFDC activities is enabled
      sync_result = sync_sfdc_activities(client: client, user: user)  # sync and update import/export timestamps
      if sync_result[:status] == "ERROR"
        sync_error_detail = sync_result[:detail].map do |m| 
          if m[:sfdc_account].present?
            sfdc_entity_detail = "'#{m[:sfdc_account][:name]}'(account sObject Id=#{m[:sfdc_account][:id]})"
          else
            sfdc_entity_detail = "'#{m[:sfdc_opportunity][:name]}'(opportunity sObject Id=#{m[:sfdc_opportunity][:id]})"
          end

          (m[:status] == "ERROR" ? "x Failure:  Error at #{m[:failure_method_location]}." : "✓ Success: ") + " '#{m[:opportunity][:name]}'(opportunity id=#{m[:opportunity][:id]}) <-> (SFDC)#{sfdc_entity_detail}  detail: #{m[:detail]}"
        end.join("\n\n")
        puts "****SFDC**** Error at SalesforceController.sync_sfdc_activities() in #{method_name} during sync of activities for user=#{ user.email } org=#{ user.organization.name }. Details: #{ sync_error_detail }"
      end
    end
  end

  # Links a CS account to a Salesforce account.  If a Power User or trial/Chrome User links a SFDC account, then automatically import the SFDC contacts.
  def link_salesforce_account
    # One CS Account can be linked to many Salesforce Accounts
    salesforce_account = SalesforceAccount.find_by(id: params[:salesforce_id], contextsmith_organization_id: current_user.organization_id)
    if !salesforce_account.nil?
      account = Account.find_by_id(params[:account_id])
      salesforce_account.account = account
      salesforce_account.save

      # After linking, copy values in standard fields from SFDC -> CS
      sfdc_client = SalesforceService.connect_salesforce(user: current_user)

      if sfdc_client.present?
        update_result = Account.update_standard_fields_from_sfdc(client: sfdc_client, accounts: [account], sfdc_fields_mapping: EntityFieldsMetadatum.get_sfdc_fields_mapping_for(organization_id: current_user.organization_id, entity_type: EntityFieldsMetadatum::ENTITY_TYPE[:Account]))
        puts "****SFDC**** Error while attempting to automatically update standard fields after linking a CS and Salesforce Account.  Salesforce Account \"#{salesforce_account.salesforce_account_name}\" (sfdc_id='#{salesforce_account.salesforce_account_id}') to CS Account \"#{account.name}\" (account_id='#{account.id}').  #{ update_result[:result] } Details: #{ update_result[:detail] }" if update_result[:status] == "ERROR"
        # Then copy values in custom fields from SFDC -> CS
        load_result = Account.update_custom_fields_from_sfdc(client: sfdc_client, account_id: account.id, sfdc_account_id: salesforce_account.salesforce_account_id, account_custom_fields: CustomFieldsMetadatum.where("organization_id = ? AND entity_type = ? AND salesforce_field is not null", current_user.organization_id, CustomFieldsMetadatum.validate_and_return_entity_type(CustomFieldsMetadatum::ENTITY_TYPE[:Account], true)))
        puts "****SFDC**** Error while attempting to automatically update custom fields after linking a CS and Salesforce Account.  Salesforce Account \"#{salesforce_account.salesforce_account_name}\" (sfdc_id='#{salesforce_account.salesforce_account_id}') to CS Account \"#{account.name}\" (account_id='#{account.id}').  #{ load_result[:result] } Details: #{ load_result[:detail] }" if load_result[:status] == "ERROR"
        
        # For Power Users and trial/Chrome Users: Automatically import SFDC contacts, then add all SFDC contacts as pending members ('Suggested People') in all opportunities in the linked CS account 
        if current_user.power_or_trial_only?
          puts "User #{current_user.email} (id='#{current_user.id}', role='#{current_user.role})' has linked Account '#{salesforce_account.account.name}' to SFDC Account '#{salesforce_account.salesforce_account_name}'!"
          SalesforceController.import_sfdc_contacts_and_add_as_members(client: sfdc_client, account: salesforce_account.account, sfdc_account: salesforce_account) 
        end
      else
        puts "****SFDC**** Salesforce error in SalesforceController.link_salesforce_account: Cannot establish a Salesforce connection!"
      end
    end

    respond_to do |format|
      format.html { redirect_to URI.escape(request.referer, ".") }
    end
  end

  # Links a CS Opportunity to a Salesforce Opportunity.
  def link_salesforce_opportunity
    # One CS Opportunity can link to many Salesforce Opportunities
    salesforce_opp = SalesforceOpportunity.find_by(id: params[:salesforce_id])
    if !salesforce_opp.nil?
      project = Project.find_by_id(params[:project_id])
      salesforce_opp.project = project
      salesforce_opp.save

      # After linking, copy values in standard fields from SFDC -> CS
      sfdc_client = SalesforceService.connect_salesforce(user: current_user)

      if sfdc_client.present?
        update_result = Project.update_standard_fields_from_sfdc(client: sfdc_client, opportunities: [project], sfdc_fields_mapping: EntityFieldsMetadatum.get_sfdc_fields_mapping_for(organization_id: current_user.organization_id, entity_type: EntityFieldsMetadatum::ENTITY_TYPE[:Project]))
        puts "****SFDC**** Error while attempting to automatically update standard fields after linking a CS and Salesforce Opportunity.  Salesforce Opportunity \"#{salesforce_opp.name}\" (sfdc_id='#{salesforce_opp.salesforce_opportunity_id}') to CS Opportunity \"#{project.name}\" (project_id='#{project.id}').  #{ update_result[:result] } Details: #{ update_result[:detail] }" if update_result[:status] == "ERROR"
        # Then copy values in custom fields from SFDC -> CS
        load_result = Project.update_custom_fields_from_sfdc(client: sfdc_client, project_id: project.id, sfdc_opportunity_id: salesforce_opp.salesforce_opportunity_id, opportunity_custom_fields: CustomFieldsMetadatum.where("organization_id = ? AND entity_type = ? AND salesforce_field is not null", current_user.organization_id, CustomFieldsMetadatum.validate_and_return_entity_type(CustomFieldsMetadatum::ENTITY_TYPE[:Project], true)))
        puts "****SFDC**** Error while attempting to automatically update custom fields after linking a CS and Salesforce Opportunity.  Salesforce Opportunity \"#{salesforce_opp.name}\" (sfdc_id='#{salesforce_opp.salesforce_opportunity_id}') to CS Opportunity \"#{project.name}\" (project_id='#{project.id}').  #{ load_result[:result] } Details: #{ load_result[:detail] }" if load_result[:status] == "ERROR"
      else
        puts "****SFDC**** Salesforce error in SalesforceController.link_salesforce_opportunity: Cannot establish a Salesforce connection!"
      end
    end

    respond_to do |format|
      format.html { redirect_to settings_salesforce_opportunities_path }
    end
  end

  # Import/load a list of SFDC Accounts or SFDC Opportunities (that are of mapped SFDC Accounts) into local CS models, or import SFDC Activities into CS Opportunities. 
  # For Accounts/Opportunities -- This will also refreshes/updates the standard and custom field values of mapped accounts or opportunities.
  # For Activities -- use the explicit (primary) mapping of SFDC and CS Opportunities, or the implicit parent/child relation of CS opportunity to a SFDC Account through mapping of SFDC Account to CS Account.  For all active and confirmed opportunities visible to admin.
  # For Contacts -- TODO: need to reimplement!
  # Note: this will import even if CustomConfig setting is disabled, because we are explicitly importing; if it is enabled, we will save the timestamp when we performed the import.
  def import_salesforce
    sfdc_oauthuser = SalesforceController.get_sfdc_oauthuser(user: current_user)
    sfdc_client = SalesforceService.connect_salesforce(sfdc_oauthuser: sfdc_oauthuser)

    unless sfdc_client.nil?  # unless SFDC connection error
      case params[:entity_type]
      when "account"
        import_result = SalesforceAccount.load_accounts(sfdc_client, current_user.organization_id)
        if import_result[:status] == "ERROR"
          error_detail = "Error while attempting to import Salesforce accounts.  Result: #{ import_result[:result] } Details: #{ import_result[:detail] }"
          render_internal_server_error("import_salesforce#account()", "SalesforceAccount.load_accounts()", error_detail)
          return
        end
        refresh_fields(params[:entity_type]) # refresh/update the standard and custom field values of mapped accts
        return
      when "project"
        if current_user.admin?
          import_result = SalesforceOpportunity.load_opportunities(client: sfdc_client, organization: current_user.organization)
        else
          import_result = SalesforceOpportunity.load_opportunities(client: sfdc_client, user: current_user)
        end

        if import_result[:status] == "ERROR"
          error_detail = "Error while attempting to import Salesforce opportunities.  Result: #{ import_result[:result] } Details: #{ import_result[:detail] }"
          render_internal_server_error("import_salesforce#project()", "SalesforceOpportunity.load_opportunities()", error_detail)
          return
        end
        refresh_fields(params[:entity_type]) # refresh/update the standard and custom field values of mapped opps
        return
      when "activity"
        if sfdc_oauthuser.present? && sfdc_oauthuser.user_id.blank? 
          # organization
          import_sfdc_act_config = CustomConfiguration.salesforce_sync.where("((config_value::jsonb)->>'activities')::jsonb ?| array[:keys] AND user_id IS NULL", keys: ['import']).find_by(organization_id: current_user.organization_id)
        else
          # individual
          import_sfdc_act_config = CustomConfiguration.salesforce_sync.where("((config_value::jsonb)->>'activities')::jsonb ?| array[:keys]", keys: ['import']).find_by(organization_id: current_user.organization_id, user_id: current_user.id)
        end

        # Ignores exported CS data residing on SFDC.
        # TODO: Issue #829 Need to allow SFDC import of activities to continue even after encountering an error.  Use new sync_salesforce code as guide.
        method_name = "import_salesforce#activity()"
        filter_predicates_h = {}
        filter_predicates_h["entity"] = params[:entity_pred].strip
        filter_predicates_h["activityhistory"] = params[:activityhistory_pred].strip

        #puts "******************** #{ method_name } ... filter_predicates_h= #{ filter_predicates_h }", 
        opportunities = Project.visible_to_admin(current_user.organization_id).is_active.is_confirmed.includes(:salesforce_opportunity) # all active opportunities because "admin" role can see everything
        # opportunities = Project.visible_to(current_user.organization_id, current_user.id).is_active.is_confirmed.includes(:salesforce_opportunity)
        no_linked_sfdc = opportunities.none?{ |o| o.is_linked_to_SFDC? }

        # Nothing to do if no opportunities or linked SFDC entities
        if opportunities.blank? || no_linked_sfdc
          sfdc_client = nil
          render plain: '' 
          return 
        end

        prev_import_ts = DateTime.parse(import_sfdc_act_config.config_value['activities']['import']).utc if import_sfdc_act_config.config_value['activities']['import'].present?
        new_import_ts = Time.now.utc

        opportunities.each do |p|
          load_result = p.load_salesforce_activities(client: sfdc_client, from_lastmodifieddate: prev_import_ts, to_lastmodifieddate: new_import_ts, filter_predicates_h: filter_predicates_h)

          if load_result[:status] == "ERROR"
            failure_method_location = "load_salesforce_activities()"
            render_internal_server_error(method_name, failure_method_location, load_result[:detail])
            return
          end
        end

        # if import SFDC activities is enabled in CustomConfiguration, save the timestamp 
        if import_sfdc_act_config.present? #&& import_sfdc_act_config.config_value['activities'].present?
          import_sfdc_act_config.config_value['activities']['import'] = new_import_ts
          import_sfdc_act_config.save
        end
      # end when params[:entity_type] = "activity"
      when "contacts"
        if sfdc_oauthuser.present? && sfdc_oauthuser.user_id.blank? 
          # organization
          import_sfdc_contacts_config = CustomConfiguration.salesforce_sync.where("((config_value::jsonb)->>'contacts')::jsonb ?| array[:keys] AND user_id IS NULL", keys: ['import']).find_by(organization_id: current_user.organization_id)
        else
          # individual
          import_sfdc_contacts_config = CustomConfiguration.salesforce_sync.where("((config_value::jsonb)->>'contacts')::jsonb ?| array[:keys]", keys: ['import']).find_by(organization_id: current_user.organization_id, user_id: current_user.id)
        end
        ### TODO: need to reimplement!
      else
        error_detail = "Invalid entity_type parameter passed to import_salesforce(). entity_type=#{params[:entity_type]}"
        puts error_detail
        render_internal_server_error(method_name, method_name, error_detail)
        return
      end
      sfdc_client = nil
    else # SFDC connection error
      render_service_unavailable_error(method_name)
      return
    end

    render plain: ''
  end

  # Export CS Activity into the mapped SFDC Account (or Opportunity)
  # For Activities -- use the explicit (primary) mapping of SFDC and CS Opportunities, or the implicit parent/child relation of CS opportunity to a SFDC Account through mapping of SFDC Account to CS Account.  For all active and confirmed opportunities visible to admin.
  # For Contacts -- TODO: may *NOT* need to reimplement
  # Note: this will export even if CustomConfig setting is disabled, because we are explicitly exporting; if it is enabled, we will save the timestamp when we performed the export.
  def export_salesforce
    sfdc_oauthuser = SalesforceController.get_sfdc_oauthuser(user: current_user)
    case params[:entity_type]
    when "activity"
      # Activities in CS (excluding imported SFDC activity) are exported into the remote SFDC Account (or Opportunity).
      if sfdc_oauthuser.present? && sfdc_oauthuser.user_id.blank? 
        # organization
        export_sfdc_act_config = CustomConfiguration.salesforce_sync.where("((config_value::jsonb)->>'activities')::jsonb ?| array[:keys] AND user_id IS NULL", keys: ['export']).find_by(organization_id: current_user.organization_id)
      else
        # individual
        export_sfdc_act_config = CustomConfiguration.salesforce_sync.where("((config_value::jsonb)->>'activities')::jsonb ?| array[:keys]", keys: ['export']).find_by(organization_id: current_user.organization_id, user_id: current_user.id)
      end

      method_name = "export_salesforce#activity()"
      opportunities = Project.visible_to_admin(current_user.organization_id).is_active.is_confirmed.includes(:salesforce_opportunity) # all mappings for this user's organization
      # opportunities = Project.visible_to(current_user.organization_id, current_user.id).is_active.is_confirmed.includes(:salesforce_opportunity)
      no_linked_sfdc = opportunities.none?{ |o| o.is_linked_to_SFDC? }

      # Nothing to do if no opportunities or linked SFDC entities
      if opportunities.blank? || no_linked_sfdc
        render plain: '' 
        return 
      end

      sfdc_client = SalesforceService.connect_salesforce(sfdc_oauthuser: sfdc_oauthuser)

      unless sfdc_client.nil?  # unless connection error

        prev_export_ts = DateTime.parse(export_sfdc_act_config.config_value['activities']['export']).utc if export_sfdc_act_config.config_value['activities']['export'].present?
        new_export_ts = Time.now.utc

        opportunities.each do |s|
          # TODO: Issue #829 Need to allow SFDC export of activities to continue even after encountering an error.  Use new sync_salesforce code as guide.
          if s.salesforce_opportunity.nil? # CS Opportunity not linked to SFDC Opportunity
            if s.account.salesforce_accounts.present? # CS Opportunity linked to SFDC Account
              s.account.salesforce_accounts.each do |sfa|
                # Save at the Account level
                # TODO: Determine if there are any new activities in opportunity 's' to export, and don't export if none?

                # Activity.delete_cs_activities(sfdc_client, sfa.salesforce_account_id, "Account", prev_export_ts, new_export_ts)

                export_result = Activity.export_cs_activities(sfdc_client, s, sfa.salesforce_account_id, "Account", prev_export_ts, new_export_ts)

                if export_result[:status] == "ERROR"
                  method_location = "Activity.export_cs_activities()"
                  error_detail = "Error while attempting to export CS activity from CS Opportunity \"#{s.name}\" (opportunity_id='#{s.id}') to Salesforce Account \"#{sfa.salesforce_account_name}\" (sfdc_id='#{sfa.salesforce_account_id}').  Details: #{ export_result[:detail] }"
                  render_internal_server_error(method_name, method_location, error_detail)
                  return
                end
              end
            end
          else # CS Opportunity linked to SFDC Opportunity
            # Save at the Opportunity level
            # TODO: Determine if there are any new activities in opportunity 's' to export, and don't export if none?

            # Activity.delete_cs_activities(sfdc_client, s.salesforce_opportunity.salesforce_opportunity_id, "Opportunity", prev_export_ts, new_export_ts)

            export_result = Activity.export_cs_activities(sfdc_client, s, s.salesforce_opportunity.salesforce_opportunity_id, "Opportunity", prev_export_ts, new_export_ts)

            if export_result[:status] == "ERROR"
              method_location = "Activity.export_cs_activities()"
              error_detail = "Error while attempting to export CS activity from CS Opportunity \"#{s.name}\" (opportunity_id='#{s.id}') to Salesforce Opportunity \"#{s.salesforce_opportunity.name}\" (sfdc_id='#{s.salesforce_opportunity.salesforce_opportunity_id}').  Details: #{ export_result[:detail] }"
              render_internal_server_error(method_name, method_location, error_detail)
              return
            end
          end
        end # End: opportunities.each do |s|

        # if export activities is enabled
        if export_sfdc_act_config.present? #&& export_sfdc_act_config.config_value['activities'].present?
          export_sfdc_act_config.config_value['activities']['export'] = new_export_ts
          export_sfdc_act_config.save
        end
      else
        render_service_unavailable_error(method_name)
        return
      end
    # end: when params[:entity_type] = "activity"
    when "contacts"
      # TODO: May *NOT* need to reimplement
      # Contacts in linked CS Accounts are exported to linked SFDC Account.
      if sfdc_oauthuser.present? && sfdc_oauthuser.user_id.blank? 
        # organization
        export_sfdc_contacts_config = CustomConfiguration.salesforce_sync.where("((config_value::jsonb)->>'contacts')::jsonb ?| array[:keys] AND user_id IS NULL", keys: ['export']).find_by(organization_id: current_user.organization_id)
      else
        # individual
        export_sfdc_contacts_config = CustomConfiguration.salesforce_sync.where("((config_value::jsonb)->>'contacts')::jsonb ?| array[:keys]", keys: ['export']).find_by(organization_id: current_user.organization_id, user_id: current_user.id)
      end
      # ...
    else
      error_detail = "Invalid entity_type parameter passed to export_salesforce(). entity_type=#{params[:entity_type]}"
      puts error_detail
      render_internal_server_error(method_name, method_name, error_detail)
      return
    end

    render plain: ''
  end

  # Updates the local CS copy of an entity then pushes change to Salesforce.
  def update_all_salesforce
    case params[:entity_type]
    when "account"
      method_name = "update_all_salesforce#account()"

      # salesforce_account = SalesforceAccount.find_by(id: params[:id])
      salesforce_account = current_user.organization.salesforce_accounts.find_by(id: params[:id])
      if salesforce_account.blank?
        detail = "Invalid SalesforceAccount id. Cannot find SalesforceAccount with id=#{params[:id]} "
        puts "****SFDC**** Salesforce error calling SalesforceAccount.find_by() in #{method_name}. Detail: #{detail}"
        render_internal_server_error(method_name, "SalesforceAccount.find_by()", detail)
        return
      end

      sfdc_client = SalesforceService.connect_salesforce(user: current_user)

      if sfdc_client.nil?
        render_service_unavailable_error(method_name)
        return
      end

      update_result = SalesforceAccount.update_all_salesforce(client: sfdc_client, salesforce_account: salesforce_account, fields: params[:fields], current_user: current_user)
      if update_result[:status] == "ERROR"
        detail = "Error while attempting to update SalesforceAccount Id=#{params[:id]}. #{ update_result[:result] } Details: #{ update_result[:detail] }"
        puts "****SFDC**** Salesforce error calling SalesforceAccount.update_all_salesforce in #{method_name}. #{detail}"
        render_internal_server_error(method_name, "SalesforceAccount.update_all_salesforce()", detail)
        return
      end
    when "opportunity"
      method_name = "update_all_salesforce#opportunity()"

      salesforce_opportunity = SalesforceOpportunity.find_by(id: params[:id])
      if salesforce_opportunity.blank? || (salesforce_opportunity.salesforce_account.contextsmith_organization_id != current_user.organization_id)
        detail = "Invalid SalesforceOpportunity id. Cannot find SalesforceOpportunity with id=#{params[:id]} "
        puts "****SFDC**** Salesforce error calling SalesforceOpportunity.find_by() in #{method_name}. Detail: #{detail}"
        render_internal_server_error(method_name, "SalesforceOpportunity.find_by()", detail)
        return
      end

      sfdc_client = SalesforceService.connect_salesforce(user: current_user)

      if sfdc_client.nil?
        render_service_unavailable_error(method_name)
        return
      end

      update_result = SalesforceOpportunity.update_all_salesforce(client: sfdc_client, salesforce_opportunity: salesforce_opportunity, fields: params[:fields], current_user: current_user)
      if update_result[:status] == "ERROR"
        detail = "Error while attempting to update SalesforceOpportunity Id=#{params[:id]}. #{ update_result[:result] } Details: #{ update_result[:detail] }"
        puts "****SFDC**** Salesforce error calling SalesforceOpportunity.update_all_salesforce in #{method_name}. #{detail}"
        render_internal_server_error(method_name, "SalesforceOpportunity.update_all_salesforce()", detail)
        return
      end
    when "contact"
      # Note: in order for export to SFDC to work, CS account must be linked to a SFDC account
      method_name = "update_all_salesforce#contact()"
      # puts "params[:fields]:#{params[:fields]}"

      account = Account.find_by(id: params[:fields][:account_id])
      if account.blank? || !(Account.visible_to(current_user).pluck(:id).include? account.id)
        detail = "Invalid Account id. Cannot find Account with id=#{params[:fields][:account_id]} "
        puts "****SFDC**** Salesforce error calling Account.find_by() in #{method_name}. Detail: #{detail}"
        render_internal_server_error(method_name, "Account.find_by()", detail)
        return
      end

      if params[:id] == "0" #new Contact
        contact = Contact.new(
            first_name: params[:fields][:first_name],
            last_name: params[:fields][:last_name],
            title: params[:fields][:title],
            department: params[:fields][:department],
            email: params[:fields][:email],
            phone: params[:fields][:phone],
            account_id: params[:fields][:account_id],
            # source: params[:fields][:source],
            # external_source_id: params[:fields][:external_source_id]
          )
        if !contact.save
          e = contact.errors.messages
          error_messages = e.keys.select{|k| e[k].present? }.map{ |k| "#{k} #{e[k][1]}: #{e[k][0]}"}.join(', ')
          detail = "Cannot create new Contact. Errors: #{error_messages} "
          puts "****SFDC**** Salesforce error: Cannot create contact using Contact.new in #{method_name}. Params: #{params[:fields]}  Errors: #{error_messages}"
          render_internal_server_error(method_name, "Contact.new()", detail)
          return
        end
      else # update Contact
        contact = Contact.find_by(id: params[:id])
        if contact.blank? || !(Account.visible_to(current_user).pluck(:id).include? contact.account_id) # || (contact.account.organization_id != current_user.organization_id) 
          detail = "Invalid Contact id. Cannot find Contact with id=#{params[:id]} "
          puts "****SFDC**** Salesforce error calling Contact.find() in #{method_name}. Detail: #{detail}"
          render_internal_server_error(method_name, "Contact.find()", detail)
          return
        end

        if !contact.update(first_name: params[:fields][:first_name],
            last_name: params[:fields][:last_name],
            title: params[:fields][:title],
            department: params[:fields][:department],
            email: params[:fields][:email],
            phone: params[:fields][:phone],
            account_id: params[:fields][:account_id],
            #source: params[:fields][:source],
            #external_source_id: params[:fields][:external_source_id]
        )
          e = contact.errors.messages
          error_messages = e.keys.select{|k| e[k].present? }.map{ |k| "#{k} #{e[k][1]}: #{e[k][0]}"}.join(', ')
          detail = "Cannot update Contact. Errors: #{error_messages} "
          puts "****SFDC**** Salesforce error: Cannot update contact using contact.update in #{method_name}. Params: #{params[:fields]}  Errors: #{error_messages}"
          render_internal_server_error(method_name, "Contact.update()", detail)
          return
        end
      end # End: update Contact

      sfdc_client = SalesforceService.connect_salesforce(user: current_user)

      if sfdc_client.nil?
        render_service_unavailable_error(method_name)
        return
      end

      if account.salesforce_accounts.present?
        salesforce_account = account.salesforce_accounts.first
      else
        detail = "No Salesforce account linked to ContextSmith account \"#{account.name}\"! Cannot create SFDC contact! #{params[:fields][:account_id]} "
        puts "****SFDC**** Salesforce error creating/updating Salesforce contact in #{method_name}. Detail: #{detail}"
        render_internal_server_error(method_name, "Account.find()", detail)
        return
      end

      update_result = Contact.update_all_salesforce(client: sfdc_client, sfdc_account_id: salesforce_account.salesforce_account_id, contact: contact) # params[:fields], current_user

      if update_result[:status] == "ERROR"
        detail = "Error while attempting to create/update SFDC Contact Id='#{contact.external_source_id}' for CS contact Id='#{contact.id}'. #{ update_result[:result] } Details: #{ update_result[:detail] }"
        puts "****SFDC**** Salesforce error calling Contact.update_all_salesforce in #{method_name}. #{detail}"
        render_internal_server_error(method_name, "Contact.update_all_salesforce()", detail)
        return
      end

      # Finally, update CS contact to point back to SFDC contact
      if !contact.update(source: "Salesforce",
                         external_source_id: update_result[:result]
        )
        e = contact.errors.messages
        error_messages = e.keys.select{|k| e[k].present? }.map{ |k| "#{k} #{e[k][1]}: #{e[k][0]}"}.join(', ')
        detail = "Cannot update Contact sfdc_id '#{update_result[:status]}'. Errors: #{error_messages} "
        puts "****SFDC**** Salesforce error: Cannot update contact's external_source_id (id='#{update_result[:status]}') using contact.update in #{method_name}. Params: #{params[:fields]}  Errors: #{error_messages}"
        render_internal_server_error(method_name, "Contact.update()", detail)
        return
      end
    else
      method_name = "update_all_salesforce"
      error_detail = "Invalid entity_type parameter passed to update_all_salesforce(). entity_type=#{params[:entity_type]}"
      puts "****SFDC**** #{error_detail}"
      render_internal_server_error(method_name, method_name, error_detail)
      return
    end

    render plain: ''
  end

  # Synchronize entities in CS and SFDC consisting of an import of a SFDC entity to ContextSmith, followed by an export back to SFDC, using SFDC <-> CS fields mapping.  
  # For Activities -- use the explicit (primary) mapping of SFDC and CS Opportunities, or the implicit parent/child relation of CS opportunity to a SFDC Account through mapping of SFDC Account to CS Account. Imports SFDC Activities (not exported from CS) into CS Opportunities. This is for all active and confirmed opportunities visible to admin.
  # For Contacts -- merges Contacts depending on the explicit mapping of a SFDC Account to a CS Account. ("Sync" is used loosely, because some Contacts is missing information like e-mail address). This is for all contacts in accounts visible to current_user.
  # Note: Either import or export must be enabled for the corresponding SFDC object type in CustomConfiguration in order to import or export the object respectively.
  def sync_salesforce
    method_name = "sync_salesforce()"
    case params[:entity_type]
    when "activity"
      method_name = "sync_salesforce#activity" 
      filter_predicates_h = {}
      filter_predicates_h["entity"] = params[:entity_pred].strip
      filter_predicates_h["activityhistory"] = params[:activityhistory_pred].strip
      # puts "******* filter_predicates_h= #{ filter_predicates_h }"
      sfdc_client = SalesforceService.connect_salesforce(user: current_user)
      # sfdc_client = nil  # Simulate connection error

      unless sfdc_client.nil?  # unless SFDC connection error
        sync_result = SalesforceController.sync_sfdc_activities(client: sfdc_client, user: current_user, filter_predicates_h: filter_predicates_h)  # sync and update import/export timestamps
        # sync_result = { status: "ERROR", result: nil, detail: [{opportunity: {name: "fake CS opp", id: "xxxxxxxx-made-upup-csid-xxxxxxxx"}, sfdc_account: {name: "fake SFDC acct", id: "00xxxxxxxxxxxxfake"}, status: "ERROR", failure_method_location: "some fictional location"}] }  # Simulate sync error
        if sync_result[:status] == "ERROR"
          render_internal_server_error(method_name, "(see listing)", sync_result[:detail].map do |m| 
              if m[:sfdc_account].present?
                sfdc_entity_detail = "'#{m[:sfdc_account][:name]}'(account sObject Id=#{m[:sfdc_account][:id]})"
              else
                sfdc_entity_detail = "'#{m[:sfdc_opportunity][:name]}'(opportunity sObject Id=#{m[:sfdc_opportunity][:id]})"
              end

              (m[:status] == "ERROR" ? "x Failure:  Error at #{m[:failure_method_location]}." : "✓ Success: ") + " '#{m[:opportunity][:name]}'(opportunity id=#{m[:opportunity][:id]}) <-> (SFDC)#{sfdc_entity_detail}  detail: #{m[:detail]}"
            end.join("\n\n"))
          return
        end
        # if no errors, proceed normally
      else
        render_service_unavailable_error(method_name)
        return
      end
    # end when params[:entity_type] = "activity"
    when "contacts"
      method_name = "sync_salesforce#contacts"
      sfdc_oauthuser = SalesforceController.get_sfdc_oauthuser(user: current_user)
      if sfdc_oauthuser.present? && sfdc_oauthuser.user_id.blank? 
        # organization
        sync_sfdc_contacts_config = CustomConfiguration.salesforce_sync.where("((config_value::jsonb)->>'contacts')::jsonb ?| array[:keys] AND user_id IS NULL", keys: ['import','export']).find_by(organization_id: current_user.organization_id)
      else
        # individual
        sync_sfdc_contacts_config = CustomConfiguration.salesforce_sync.where("((config_value::jsonb)->>'contacts')::jsonb ?| array[:keys]", keys: ['import','export']).find_by(organization_id: current_user.organization_id, user_id: current_user.id)
      end

      if sync_sfdc_contacts_config.present? # if import OR export SFDC contacts is enabled
        account_mapping = []
        accounts = Account.visible_to(current_user).select{|a| a.salesforce_accounts.present?}
        accounts.each do |a|
          account_mapping << [a, a.salesforce_accounts.first]
        end

        unless account_mapping.empty?  # no visible or mapped accounts
          sfdc_client = SalesforceService.connect_salesforce(user: current_user)
          # sfdc_client = nil  # Simulate connection error

          unless sfdc_client.nil?  # unless SFDC connection error
            sync_result_messages = []
            error_occurred = false

            prev_import_ts = DateTime.parse(sync_sfdc_contacts_config.config_value['contacts']['import']).utc if sync_sfdc_contacts_config.config_value['contacts']['import'].present?
            prev_export_ts = DateTime.parse(sync_sfdc_contacts_config.config_value['contacts']['export']).utc if sync_sfdc_contacts_config.config_value['contacts']['export'].present?
            new_sync_ts = Time.now.utc
            # puts "\n\n\n\tprev_import_ts: #{prev_import_ts}\n\tprev_export_ts: #{prev_export_ts}\t\n new_sync_ts: #{new_sync_ts}"

            account_mapping.each do |m|
              a = m[0]
              sfa = m[1]

              if !sync_sfdc_contacts_config.config_value['contacts']['import'].nil? # import SFDC contacts is enabled
                # Import Contacts from SFDC to ContextSmith 
                import_result = Contact.load_salesforce_contacts(sfdc_client, a.id, sfa.salesforce_account_id, prev_import_ts, new_sync_ts)
                failure_method_location = "Contact.load_salesforce_contacts()"

                if import_result[:status] == "ERROR"
                  puts "****SFDC**** Error at #{failure_method_location} while attempting to import contacts from Salesforce Account \"#{sfa.salesforce_account_name}\" (sfdc_id='#{sfa.salesforce_account_id}') to CS Account \"#{a.name}\" (account_id='#{a.id}').  #{ import_result[:result] } Details: #{ import_result[:detail] }"
                  sync_result_messages << { status: import_result[:status], account: { name: a.name, id: a.id }, sfdc_account: { name: sfa.salesforce_account_name, id: sfa.salesforce_account_id }, failure_method_location: failure_method_location, detail: import_result[:result] + " " + import_result[:detail] }
                  error_occurred = true
                else # import_result[:status] == SUCCESS
                  sync_result_messages << { status: import_result[:status], account: { name: a.name, id: a.id }, sfdc_account: { name: sfa.salesforce_account_name, id: sfa.salesforce_account_id }, detail: import_result[:result] + " " + import_result[:detail] } 
                end
              end

              if !sync_sfdc_contacts_config.config_value['contacts']['export'].nil? # export SFDC contacts is enabled
                # Export ContextSmith Contacts out to SFDC
                export_result = Contact.export_cs_contacts(sfdc_client, a.id, sfa.salesforce_account_id, prev_export_ts, new_sync_ts)
                failure_method_location = "Contact.export_cs_contacts()"

                if export_result[:status] == "ERROR"
                  puts "****SFDC**** Error at #{failure_method_location} while attempting to export contacts from CS Account \"#{a.name}\" (account_id='#{a.id}') to Salesforce Account \"#{sfa.salesforce_account_name}\" (sfdc_id='#{sfa.salesforce_account_id}').  #{ import_result[:result] } Details: #{ import_result[:detail] }"
                  sync_result_messages << { status: export_result[:status], account: { name: a.name, id: a.id }, sfdc_account: { name: sfa.salesforce_account_name, id: sfa.salesforce_account_id }, failure_method_location: failure_method_location, detail: export_result[:detail] }
                  error_occurred = true
                else # export_result[:status] == SUCCESS
                  sync_result_messages << { status: export_result[:status], account: { name: a.name, id: a.id }, sfdc_account: { name: sfa.salesforce_account_name, id: sfa.salesforce_account_id } } 
                end
              end
            end #end: account_mapping.each

            #puts "\n\n==> Sync result messages: #{sync_result_messages}\n\n"
            if error_occurred
              render_internal_server_error(method_name, "(see listing)", sync_result_messages.map{ |m| (m[:status] == "ERROR" ? "x Failure:  Error at #{m[:failure_method_location]}." : "✓ Success: ") + " '#{m[:account][:name]}'(account id=#{m[:account][:id]}) <-> (SFDC)'#{m[:sfdc_account][:name]}'(account sObject Id=#{m[:sfdc_account][:id]})  detail: #{m[:detail]}" }.join("\n\n"))
              return
            else
              # Update the import/export contacts timestamp
              sync_sfdc_contacts_config.config_value['contacts']['import'] = new_sync_ts if !sync_sfdc_contacts_config.config_value['contacts']['import'].nil? # import SFDC contacts is enabled
              sync_sfdc_contacts_config.config_value['contacts']['export'] = new_sync_ts if !sync_sfdc_contacts_config.config_value['contacts']['export'].nil? # export SFDC contacts is enabled
              sync_sfdc_contacts_config.save
            end
          else
            render_service_unavailable_error(method_name)
            return
          end
        end
      end # end: if import/export SFDC contacts is enabled
    # end: when params[:entity_type] = "contacts"
    else
      error_detail = "Invalid entity_type parameter passed to sync_salesforce(). entity_type=#{params[:entity_type]}"
      puts error_detail
      render_internal_server_error(method_name, method_name, error_detail)
      return
    end

    render plain: ''
  end

  # Import (update) SFDC field values into native and custom CS fields according to the explicit mapping of a field of a SFDC opportunity to the field of a CS opportunity, or a field of a SFDC account to a field of a CS account. This is for all active accounts in current_user's organization OR for all active and confirmed opportunities visible to current_user.
  # Parameters:  entity_type - "account" or "opportunity".
  # Note: While it is typical to have a 1:1 mapping between CS and SFDC entities, it is possible to have a 1:N mapping.  If multiple SFDC accounts are mapped to the same CS account, the first mapping found will be used for the update. If multiple SFDC opportunities are mapped to the same CS Opportunity, an update will be carried out for each mapping.
  def refresh_fields(entity_type)
    method_name = "refresh_fields()"

    sfdc_client = SalesforceService.connect_salesforce(user: current_user)

    if sfdc_client.nil?
      render_service_unavailable_error(method_name)
      return
    end

    if entity_type == "account"
      refresh_result = SalesforceAccount.refresh_fields(sfdc_client, current_user)
      if refresh_result[:status] == "ERROR"
        render_internal_server_error(method_name, refresh_result[:detail][:failure_method_location], refresh_result[:detail][:detail])
        return
      end
    elsif entity_type == "project"
      refresh_result = SalesforceOpportunity.refresh_fields(sfdc_client, current_user)
      if refresh_result[:status] == "ERROR"
        render_internal_server_error(method_name, refresh_result[:detail][:failure_method_location], refresh_result[:detail][:detail])
        return
      end
    else
      error_detail = "Invalid entity_type parameter passed to refresh_fields(). entity_type=#{entity_type}"
      puts error_detail
      render_internal_server_error(method_name, method_name, error_detail)
      return
    end

    render plain: ''
  end

  def remove_account_link
    salesforce_account = SalesforceAccount.eager_load(:account).find_by(id: params[:id], contextsmith_organization_id: current_user.organization_id)

    if !salesforce_account.nil?
      salesforce_account.salesforce_opportunities.destroy_all
      salesforce_account.contextsmith_account_id = nil
      salesforce_account.save
    end

    respond_to do |format|
      format.html { redirect_to URI.escape(request.referer, ".") }
    end

  end

  def remove_opportunity_link
    salesforce_opp = SalesforceOpportunity.find_by(id: params[:id])

    if !salesforce_opp.nil?
      salesforce_opp.contextsmith_project_id = nil
      salesforce_opp.save
    end

    respond_to do |format|
      format.html { redirect_to URI.escape(request.referer, ".") }
    end
  end

  def disconnect
    # delete salesforce oauth_user
    salesforce_user = OauthUser.find_by(id: params[:id])
    salesforce_user.destroy if salesforce_user.present?

    # if current_user.admin?
    #   salesforce_sync_config = current_user.organization.custom_configurations.find_by(config_type: CustomConfiguration::CONFIG_TYPE[:Salesforce_sync], user_id: nil)
    # else
    #   salesforce_sync_config = current_user.organization.custom_configurations.find_by(config_type: CustomConfiguration::CONFIG_TYPE[:Salesforce_sync], user_id: current_user.id)
    # end
    # salesforce_sync_config.destroy if salesforce_sync_config.present?

    respond_to do |format|
      format.html { redirect_to(request.referer || settings_path) }
    end
  end

  # Gets Salesforce (custom) fields from SFDC connection (client) in the form of the following hash:
  #   :sfdc_account_fields -- a list of SFDC account field names mapped to the field labels (visible to the user) in the form of [["acctfield1name", "acctfield1label (acctfield1name)"], ["acctfield2name", "acctfield2label (acctfield2name)"], ...]
  #   :sfdc_account_fields_metadata -- a hash of SFDC account field names with metadata info in the form of {"acctfield1" => {type: acctfield1.type, custom: acctfield1.custom, updateable: acctfield1.updateable, nillable: acctfield1.nillable} }
  #   :sfdc_opportunity_fields -- a list of SFDC opportunity field names mapped to the field labels (visible to the user) in a similar to :sfdc_account_fields
  #   :sfdc_opportunity_fields_metadata -- similar to :sfdc_account_fields_metadata for sfdc_opportunity_fields
  #   :sfdc_contact_fields -- a list of SFDC contact field names mapped to the field labels (visible to the user) in a similar to :sfdc_account_fields
  #   :sfdc_contact_fields_metadata -- similar to :sfdc_account_fields_metadata for sfdc_contact_fields
  # Returns {} if there is no SFDC connection detected for this Organization, or if there was a SFDC connection error.
  def self.get_salesforce_fields(client: , custom_fields_only: false)
    return {} if client.nil?

    sfdc_account_fields = {}
    sfdc_account_fields_metadata = {}
    sfdc_opportunity_fields = {}
    sfdc_opportunity_fields_metadata = {}
    sfdc_contact_fields = {}
    sfdc_contact_fields_metadata = {}

    entity_describe = client.describe('Account')
    entity_describe.fields.each do |f|
      sfdc_account_fields[f.name] = f.label + " (" + f.name + ")" if (!custom_fields_only || f.custom)
      metadata = {}
      metadata["type"] = f.type
      metadata["custom"] = f.custom
      metadata["updateable"] = f.updateable
      metadata["nillable"] = f.nillable
      sfdc_account_fields_metadata[f.name] = metadata
    end
    entity_describe = client.describe('Opportunity')
    entity_describe.fields.each do |f|
      sfdc_opportunity_fields[f.name] = f.label + " (" + f.name + ")" if (!custom_fields_only || f.custom)
      metadata = {}
      metadata["type"] = f.type
      metadata["custom"] = f.custom
      metadata["updateable"] = f.updateable
      metadata["nillable"] = f.nillable
      sfdc_opportunity_fields_metadata[f.name] = metadata
    end
    entity_describe = client.describe('Contact')
    entity_describe.fields.each do |f|
      sfdc_contact_fields[f.name] = f.label + " (" + f.name + ")" if (!custom_fields_only || f.custom)
      metadata = {}
      metadata["type"] = f.type
      metadata["custom"] = f.custom
      metadata["updateable"] = f.updateable
      metadata["nillable"] = f.nillable
      sfdc_contact_fields_metadata[f.name] = metadata
    end
    # entity_describe = client.describe('OpportunityStage')

    sfdc_account_fields = sfdc_account_fields.sort_by { |k,v| v.upcase }
    sfdc_opportunity_fields = sfdc_opportunity_fields.sort_by { |k,v| v.upcase }
    sfdc_contact_fields = sfdc_contact_fields.sort_by { |k,v| v.upcase }

    return { sfdc_account_fields: sfdc_account_fields, sfdc_account_fields_metadata: sfdc_account_fields_metadata, sfdc_opportunity_fields: sfdc_opportunity_fields, sfdc_opportunity_fields_metadata: sfdc_opportunity_fields_metadata, sfdc_contact_fields: sfdc_contact_fields, sfdc_contact_fields_metadata: sfdc_contact_fields_metadata }
  end

  # Import SFDC contacts from sfdc_account, then add all SFDC contacts as pending members ('Suggested People') in all opportunities in the linked CS account 
  def self.import_sfdc_contacts_and_add_as_members(client: , account: , sfdc_account: )
    puts "Automatically importing SFDC contacts from SFDC Account '#{ sfdc_account.salesforce_account_name }' into Account '#{ account.name }' and adding SFDC contacts as pending members of its opportunities..."

    unless client.nil?  # if valid connection 
      load_result = Contact.load_salesforce_contacts(client, sfdc_account.contextsmith_account_id, sfdc_account.salesforce_account_id)
      if load_result[:status] == "SUCCESS"
        puts "Contacts successfully loaded."
      else # Salesforce error occurred
        puts "Error calling Contact.load_salesforce_contacts() in SalesforceController#import_sfdc_contacts_and_add_as_members! Attempted to load Contacts from Salesforce Account \"#{sfdc_account.salesforce_account_name}\" (sfdc_id='#{sfdc_account.salesforce_account_id}') to CS Account \"#{account.name}\" (account_id='#{sfdc_account.contextsmith_account_id}').  #{load_result[:result]} Details: #{ load_result[:detail] }"
      end
    end

    # Add all SFDC contacts found in CS account to pending members of all opportunities in this CS account if not already a member of the opportunity, even SFDC contacts to whom the current user does not have visibility!
    sfdc_contacts = account.contacts.select { |c| c.is_source_from_salesforce? }
    account.projects.each do |p|
      project_contact_ids = p.contacts_all.pluck(:contact_id)

      sfdc_contacts.each { |sfc| ProjectMember.create(project: p, contact: sfc, status: ProjectMember::STATUS[:Pending]) unless project_contact_ids.include?(sfc.id)  # if contact is not a project member in this opportunity, add as a suggested member
      }
    end
  end

  private

  ### TODO: get_show_data and load_timeline are copies from ProjectsController, should be combined for better maintenance/to keep in sync with projects#show
  def get_show_data
    # metrics
    @project_close_date = @project.close_date.nil? ? nil : @project.close_date.strftime('%Y-%m-%d')
    @project_renewal_date = @project.renewal_date.nil? ? nil : @project.renewal_date.strftime('%Y-%m-%d')
    @project_open_tasks_count = @project.notifications.open.count

    # Removing RAG status - old metric
    # project_rag_score = @project.activities.latest_rag_score.first
    # if project_rag_score
    #   @project_rag_status = project_rag_score['rag_score']
    # end

    # old metrics
    # @project_risk_score = @project.new_risk_score(current_user.time_zone)
    # @project_pinned_count = @project.activities.pinned.visible_to(current_user.email).count
    # @project_open_risks_count = @project.notifications.open.alerts.count
    # @project_last_activity_date = @project.activities.where.not(category: [Activity::CATEGORY[:Note], Activity::CATEGORY[:Alert]]).maximum("activities.last_sent_date")
    # project_last_touch = @project.conversations.find_by(last_sent_date: @project_last_activity_date)
    # @project_last_touch_by = project_last_touch ? project_last_touch.from[0].personal : "--"

    # project people
    @project_members = @project.project_members
    project_subscribers = @project.subscribers
    @daily_subscribers = project_subscribers.daily
    @weekly_subscribers = project_subscribers.weekly
    @suggested_members = @project.project_members_all.pending
    @user_subscription = project_subscribers.where(user: current_user).take

    @salesforce_base_URL = OauthUser.get_salesforce_instance_url(current_user.organization_id)
    @clearbit_domain = @project.account.domain? ? @project.account.domain : (@project.account.contacts.present? ? @project.account.contacts.first.email.split("@").last : "")

    # for merging projects, for future use
    # @account_projects = @project.account.projects.where.not(id: @project.id).pluck(:id, :name)
  end

  # Copied directly from ProjectsController#load_timeline
  def load_timeline
    activities = @project.activities.visible_to(current_user.email).includes(:notifications, :attachments, :comments)
    @pinned_ids = activities.pinned.ids.reverse # get ids of Key Activities to show number on stars
    # filter by categories
    @filter_category = []
    if params[:category].present?
      @filter_category = params[:category].split(',')

      # special cases: if Attachment or Pinned category filters selected, remove from normal WHERE condition and handle differently below
      if @filter_category.include?(Notification::CATEGORY[:Attachment]) || @filter_category.include?(Activity::CATEGORY[:Pinned])
        where_categories = @filter_category - [Notification::CATEGORY[:Attachment], Activity::CATEGORY[:Pinned]]
        category_condition = "activities.category IN ('#{where_categories.join("','")}')"

        # Attachment filter selected, need to INCLUDE conversations with child attachments but NOT EXCLUDE other categories chosen with filter
        if @filter_category.include?(Notification::CATEGORY[:Attachment])
          activities = activities.joins("LEFT JOIN notifications AS attachment_notifications ON attachment_notifications.activity_id = activities.id AND attachment_notifications.category = '#{Notification::CATEGORY[:Attachment]}'").distinct
          category_condition += " OR (activities.category = '#{Activity::CATEGORY[:Conversation]}' AND attachment_notifications.id IS NOT NULL)"
        end

        # Pinned filter selected, need to INCLUDE pinned activities regardless of type but NOT EXCLUDE other categories chosen with filter
        if @filter_category.include?(Activity::CATEGORY[:Pinned])
          category_condition += " OR activities.is_pinned IS TRUE"
        end

        activities = activities.where(category_condition)
      else
        activities = activities.where(category: @filter_category)
      end
    end
    # filter by people
    @filter_email = []
    if params[:emails].present?
      @filter_email = params[:emails].split(',')
      # filter for Meetings/Conversations where all people participated
      where_email_clause = @filter_email.map { |e| "\"from\" || \"to\" || \"cc\" @> '[{\"address\":\"#{e}\"}]'::jsonb" }.join(' AND ')
      # filter for Notes written by any people included
      users = User.where(email: @filter_email).pluck(:id)
      where_email_clause += " OR posted_by IN ('#{users.join("','")}')" if users.present?
      activities = activities.where(where_email_clause)
    end
    # filter by time
    @filter_time = []
    if params[:time].present?
      @filter_time = params[:time].split(',').map(&:to_i)
      # filter for Meetings/Notes in time range + Conversations that have at least 1 email message in time range
      activities = activities.where("EXTRACT(EPOCH FROM last_sent_date) BETWEEN #{@filter_time[0]} AND #{@filter_time[1]} OR ((email_messages->0->>'sentDate')::integer <= #{@filter_time[1]} AND (email_messages->-1->>'sentDate')::integer >= #{@filter_time[0]} )")
    end
    # pagination, must be after filters to have accurate count!
    page_size = 10
    @page = params[:page].blank? ? 1 : params[:page].to_i
    @last_page = activities.count <= (page_size * @page) # check whether there is another page to load
    activities = activities.limit(page_size).offset(page_size * (@page - 1))
    @activities_by_month = activities.group_by {|a| Time.zone.at(a.last_sent_date).strftime('%^B %Y') }

    @salesforce_base_URL = OauthUser.get_salesforce_instance_url(current_user.organization_id)
  end

  # Synchronize (import and export) CS and SFDC activities using previous import/export timestamps, if available. If the import and/or export operations were successful, update the respective timestamps.
  # Note: Called from scheduled (periodic) SFDC sync and the SFDC Admin panel in Settings.
  # Parameters:   client - a valid SFDC connection
  #               user - the user making the request, admin or individual (non-admin)
  #               filter_predicates_h (optional) - a hash that contains keys "entity" and "activityhistory" that are predicates applied to the WHERE clause for SFDC Accounts/Opportunities and the ActivityHistory SObject, respectively. They will be directly injected into the SOQL (SFDC) query.
  # Returns:   A hash that represents the execution status/result. Consists of:
  #             status - "SUCCESS" if operation is successful with no errors (activities exported or no activities to export); "ERROR" if any error occurred during the sync. (including partial successes)
  #             result - a message about the result of the process.
  #             detail - a list of errors or informational/warning messages.
  def self.sync_sfdc_activities(client: , user: , filter_predicates_h: nil)
    sfdc_oauthuser = SalesforceController.get_sfdc_oauthuser(user: user)
    if sfdc_oauthuser.present? && sfdc_oauthuser.user_id.blank? 
      # organization
      sync_sfdc_act_config = CustomConfiguration.salesforce_sync.where("((config_value::jsonb)->>'activities')::jsonb ?| array[:keys] AND user_id IS NULL", keys: ['import','export']).find_by(organization_id: user.organization_id)
    else
      # individual
      sync_sfdc_act_config = CustomConfiguration.salesforce_sync.where("((config_value::jsonb)->>'activities')::jsonb ?| array[:keys]", keys: ['import','export']).find_by(organization_id: user.organization_id, user_id: user.id)
    end

    if sync_sfdc_act_config.present? # if import OR export SFDC activities is enabled
      opportunities = Project.visible_to_admin(user.organization_id).is_active.is_confirmed.includes(:salesforce_opportunity) # all active opportunities because "admin" role can see everything
      no_linked_sfdc = opportunities.none?{ |o| o.is_linked_to_SFDC? }

      # Nothing to do if no opportunities or linked SFDC entities
      return { status: "SUCCESS", result: nil, detail: [] } if opportunities.blank? || no_linked_sfdc

      sync_result_messages = []
      error_occurred = false

      prev_import_ts = DateTime.parse(sync_sfdc_act_config.config_value['activities']['import']).utc if sync_sfdc_act_config.config_value['activities']['import'].present?
      prev_export_ts = DateTime.parse(sync_sfdc_act_config.config_value['activities']['export']).utc if sync_sfdc_act_config.config_value['activities']['export'].present?
      new_sync_ts = Time.now.utc
      # puts "\n\n\n\tprev_import_ts: #{prev_import_ts}\n\tprev_export_ts: #{prev_export_ts}\t\n new_sync_ts: #{new_sync_ts}"

      opportunities.each do |s|
        if s.salesforce_opportunity.nil? # CS Opportunity not linked to SFDC Opportunity
          if s.account.salesforce_accounts.present? # CS Opportunity linked to SFDC Account
            s.account.salesforce_accounts.each do |sfa|
              if !sync_sfdc_act_config.config_value['activities']['import'].nil? # import SFDC activities is enabled
                # Import activities from SFDC Account level to ContextSmith Opportunity
                load_result = Activity.load_salesforce_activities(client: client, project: s, sfdc_id: sfa.salesforce_account_id, type: "Account", from_lastmodifieddate: prev_import_ts, to_lastmodifieddate: new_sync_ts, filter_predicates_h: filter_predicates_h)

                if load_result[:status] == "ERROR"
                  failure_method_location = "Activity.load_salesforce_activities()"
                  puts "****SFDC**** Error at #{failure_method_location} while attempting to import activity from Salesforce Account \"#{sfa.salesforce_account_name}\" (sfdc_id='#{sfa.salesforce_account_id}') to CS Opportunity \"#{s.name}\" (opportunity_id='#{s.id}').  #{ load_result[:result] } Details: #{ load_result[:detail] }"
                  sync_result_messages << { status: load_result[:status], opportunity: { name: s.name, id: s.id }, sfdc_account: { name: sfa.salesforce_account_name, id: sfa.salesforce_account_id }, failure_method_location: failure_method_location, detail: load_result[:result] + " " + load_result[:detail] }
                  error_occurred = true
                else # load_result[:status] == SUCCESS
                  sync_result_messages << { status: load_result[:status], opportunity: { name: s.name, id: s.id }, sfdc_account: { name: sfa.salesforce_account_name, id: sfa.salesforce_account_id }, detail: load_result[:result] + " " + load_result[:detail] } 
                end
              end

              if !sync_sfdc_act_config.config_value['activities']['export'].nil? # export SFDC activities is enabled
                # Export activities from ContextSmith Opportunity to SFDC Account level
                # TODO: Determine if there are any new activities in opportunity 's' to export, and don't export if none?

                # Activity.delete_cs_activities(client, sfa.salesforce_account_id, "Account", prev_export_ts, new_sync_ts)

                export_result = Activity.export_cs_activities(client, s, sfa.salesforce_account_id, "Account", prev_export_ts, new_sync_ts)

                if export_result[:status] == "ERROR"
                  failure_method_location = "Activity.export_cs_activities()"
                  puts "****SFDC**** Error at #{failure_method_location} while attempting to export CS activity from CS Opportunity \"#{s.name}\" (opportunity_id='#{s.id}') to Salesforce Account \"#{sfa.salesforce_account_name}\" (sfdc_id='#{sfa.salesforce_account_id}').  Details: #{ export_result[:detail] }"
                  sync_result_messages << { status: export_result[:status], opportunity: { name: s.name, id: s.id }, sfdc_account: { name: sfa.salesforce_account_name, id: sfa.salesforce_account_id }, failure_method_location: failure_method_location, detail: export_result[:result].to_s + " " + export_result[:detail].to_s }
                  error_occurred = true
                else # export_result[:status] == SUCCESS
                  sync_result_messages << { status: export_result[:status], opportunity: { name: s.name, id: s.id }, sfdc_account: { name: sfa.salesforce_account_name, id: sfa.salesforce_account_id }, detail: export_result[:result].to_s + " " + export_result[:detail].to_s } 
                end
              end
            end # end: s.account.salesforce_accounts.each do |sfa|
          end
        else # CS Opportunity linked to SFDC Opportunity
          if !sync_sfdc_act_config.config_value['activities']['import'].nil? # import SFDC activities is enabled
            # Import activities from SFDC to ContextSmith, both at Opportunity level
            load_result = Activity.load_salesforce_activities(client: client, project: s, sfdc_id: s.salesforce_opportunity.salesforce_opportunity_id, type: "Opportunity", from_lastmodifieddate: prev_import_ts, to_lastmodifieddate: new_sync_ts, filter_predicates_h: filter_predicates_h)

            if load_result[:status] == "ERROR"
              failure_method_location = "Activity.load_salesforce_activities()"
              puts "****SFDC**** Error at #{failure_method_location} while attempting to import activity from Salesforce Opportunity \"#{s.salesforce_opportunity.name}\" (sfdc_id='#{s.salesforce_opportunity.salesforce_opportunity_id}') to CS Opportunity \"#{s.name}\" (opportunity_id='#{s.id}').  #{ load_result[:result] } Details: #{ load_result[:detail] }"
              sync_result_messages << { status: load_result[:status], opportunity: { name: s.name, id: s.id }, sfdc_opportunity: { name: s.salesforce_opportunity.name, id: s.salesforce_opportunity.salesforce_opportunity_id }, failure_method_location: failure_method_location, detail: load_result[:result] + " " + load_result[:detail] }
              error_occurred = true
            else # load_result[:status] == SUCCESS
              sync_result_messages << { status: load_result[:status], opportunity: { name: s.name, id: s.id }, sfdc_opportunity: { name: s.salesforce_opportunity.name, id: s.salesforce_opportunity.salesforce_opportunity_id }, detail: load_result[:result] + " " + load_result[:detail] } 
            end
          end

          if !sync_sfdc_act_config.config_value['activities']['export'].nil? # export SFDC activities is enabled
            # Export activities from ContextSmith to SFDC, both at Opportunity level
            # TODO: Determine if there are any new activities in opportunity 's' to export, and don't export if none?

            # Activity.delete_cs_activities(client, s.salesforce_opportunity.salesforce_opportunity_id, "Opportunity", prev_export_ts, new_sync_ts)

            export_result = Activity.export_cs_activities(client, s, s.salesforce_opportunity.salesforce_opportunity_id, "Opportunity", prev_export_ts, new_sync_ts)

            if export_result[:status] == "ERROR"
              method_location = "Activity.export_cs_activities()"
              error_detail = "****SFDC**** Error at #{failure_method_location} while attempting to export CS activity from CS Opportunity \"#{s.name}\" (opportunity_id='#{s.id}') to Salesforce Opportunity \"#{s.salesforce_opportunity.name}\" (sfdc_id='#{s.salesforce_opportunity.salesforce_opportunity_id}').  Details: #{ export_result[:detail] }"
              sync_result_messages << { status: export_result[:status], opportunity: { name: s.name, id: s.id }, sfdc_opportunity: { name: s.salesforce_opportunity.name, id: s.salesforce_opportunity.salesforce_opportunity_id }, failure_method_location: failure_method_location, detail: export_result[:result].to_s + " " + export_result[:detail].to_s }
              error_occurred = true
            else # export_result[:status] == SUCCESS
              sync_result_messages << { status: export_result[:status], opportunity: { name: s.name, id: s.id }, sfdc_opportunity: { name: s.salesforce_opportunity.name, id: s.salesforce_opportunity.salesforce_opportunity_id }, detail: export_result[:result].to_s + " " + export_result[:detail].to_s } 
            end
          end
        end
      end # end: opportunities.each do |s|

      # puts "\n\n==> Sync result messages: #{sync_result_messages}\n\n"
      if error_occurred
        return { status: "ERROR", result: "SFDC sync error", detail: sync_result_messages }
      else
        # Update the import/export activities timestamp
        sync_sfdc_act_config.config_value['activities']['import'] = new_sync_ts if !sync_sfdc_act_config.config_value['activities']['import'].nil? # import SFDC activities is enabled
        sync_sfdc_act_config.config_value['activities']['export'] = new_sync_ts if !sync_sfdc_act_config.config_value['activities']['export'].nil? # export SFDC activities is enabled
        sync_sfdc_act_config.save
      end
    end # end: if import/export SFDC activities is enabled

    return { status: "SUCCESS", result: nil, detail: [] }
  end

  def render_service_unavailable_error(method_name)
    puts "****SFDC**** Salesforce service unavailable in SalesforceController.#{method_name}: Cannot establish a Salesforce connection!"
    render json: { error: "Salesforce service unavailable: cannot establish a connection" }, status: :service_unavailable #503
  end

  def render_internal_server_error(method_name, method_location, error_detail)
    puts "****SFDC**** Salesforce query error in SalesforceController.#{method_name} (#{method_location})\nDetail:\n-------\n#{error_detail}"
    render json: { error: error_detail }, status: :internal_server_error # 500
  end
end
