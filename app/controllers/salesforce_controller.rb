class SalesforceController < ApplicationController
  layout "empty", only: :index
  before_action :get_current_org_users, only: :index

  # For accessing Project#show page+tabs from a Salesforce Visualforce iframe page
  # The route is in the form GET http(s)://<root_url>/salesforce/?id=<sfdc_opportunity_id>&pid=<cs_opportunity_id> ("&actiontype=" is optional) , e.g. "https://app.contextsmith.com/salesforce?id=0014100000A88VlPVL"
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

    @actiontype = (params[:actiontype].present? && (["index", "show", "filter_timeline", "more_timeline", "pinned_tab", "tasks_tab", "insights_tab", "arg_tab"].include? params[:actiontype])) ? params[:actiontype] : 'show'

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
      elsif @actiontype == "pinned_tab"
        @pinned_activities = @project.activities.pinned.visible_to(current_user.email).includes(:comments)
      elsif @actiontype == "tasks_tab"
        # show every risk regardless of private conversation
        @notifications = @project.notifications
      elsif @actiontype == "arg_tab" # Account Relationship Graph
        @data = @project.activities.where(category: %w(Conversation Meeting))
      end
    end

    if(!params[:category].nil? and !params[:category].empty?)
      @category_param = params[:category].split(',')
    end

    if(!params[:emails].nil? and !params[:emails].empty?)
      @filter_email = params[:emails].split(',')
    end
  end

  # Links a CS account to a Salesforce account.  If a Power User or trial/Chrome User links a SFDC account, then automatically import the SFDC contacts.
  def link_salesforce_account
    # One CS Account can be linked to many Salesforce Accounts
    salesforce_account = SalesforceAccount.find_by(id: params[:salesforce_id], contextsmith_organization_id: current_user.organization_id)
    if !salesforce_account.nil?
      salesforce_account.account = Account.find_by_id(params[:account_id])
      salesforce_account.save

      # For Power Users and trial/Chrome Users: Automatically import SFDC contacts, then add all SFDC contacts as pending members ('Suggested People') in all opportunities in the linked CS account 
      if current_user.power_or_trial_only?
        puts "User #{current_user.email} (id='#{current_user.id}', role='#{current_user.role})' has linked Account '#{salesforce_account.account.name}' to SFDC Account '#{salesforce_account.salesforce_account_name}'!"
        SalesforceController.import_sfdc_contacts_and_add_as_members(client: SalesforceService.connect_salesforce(current_user.organization_id), account: salesforce_account.account, sfdc_account: salesforce_account) 
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
      salesforce_opp.project = Project.find_by_id(params[:project_id])
      salesforce_opp.save
    end

    respond_to do |format|
      format.html { redirect_to settings_salesforce_opportunities_path }
    end
  end

  # Import/load a list of SFDC Accounts/Opportunities into local CS models, or load SFDC Contacts into all corresponding mapped CS Accounts.
  def import_salesforce
    case params[:entity_type]
    when "accounts"
      SalesforceAccount.load_accounts(current_user.organization_id)
    when "opportunities"
      SalesforceOpportunity.load_opportunities(current_user.organization_id)
    when "contacts"
      # Load SFDC Contacts into CS Accounts, depending on the explicit (primary) mapping of a SFDC Account (first one) to a CS account.
      account_mapping = []
      method_name = "import_salesforce#contacts()"
      accounts = Account.visible_to(current_user)
      accounts.each do |a|
        account_mapping << [a, a.salesforce_accounts.first] if a.salesforce_accounts.present?
      end

      unless account_mapping.empty?  # no visible or mapped accounts
        client = SalesforceService.connect_salesforce(current_user.organization_id)
        #client = nil #simulate connection error
        unless client.nil?  # unless SFDC connection error
          account_mapping.each do |m|
            a = m[0]
            sfa = m[1]
            load_result = Contact.load_salesforce_contacts(client, a.id, sfa.salesforce_account_id)

            if load_result[:status] == "ERROR"
              failure_method_location = "Contact.load_salesforce_contacts()"
              error_detail = "Error while attempting to load contacts from Salesforce Account \"#{sfa.salesforce_account_name}\" (sfdc_id='#{sfa.salesforce_account_id}') to CS Account \"#{a.name}\" (account_id='#{a.id}').  #{ load_result[:result] } Details: #{ load_result[:detail] }"
              render_internal_server_error(method_name, failure_method_location, error_detail)
              return
            end
          end
        else
          render_service_unavailable_error(method_name)
          return
        end
      end
    # end when params[:entity_type] = "contacts"
    when "activities"
      # Load SFDC Activities into CS Opportunities, depending on the explicit (primary) mapping of a SFDC opportunity to a CS Opportunity, or the implicit (secondary) opportunity mapping of a SFDC account mapped to a CS account.
      # Note: Ignores exported CS data residing on SFDC
      method_name = "import_salesforce#activities()"
      filter_predicate_str = {}
      filter_predicate_str["entity"] = params[:entity_pred].strip
      filter_predicate_str["activityhistory"] = params[:activityhistory_pred].strip

      #puts "******************** #{ method_name } ... filter_predicate_str= #{ filter_predicate_str }", 
      @opportunities = Project.visible_to_admin(current_user.organization_id).is_active.is_confirmed.includes(:salesforce_opportunity) # all active opportunities because "admin" role can see everything
      no_linked_sfdc = @opportunities.none?{ |o| o.salesforce_opportunity.present? || o.account.salesforce_accounts.present? }

      # Nothing to do if no opportunities or linked SFDC entities
      if @opportunities.blank? || no_linked_sfdc
        @client = nil
        render :text => ' ' 
        return 
      end

      @client = SalesforceService.connect_salesforce(current_user.organization_id)

      unless @client.nil?  # unless connection error
        @opportunities.each do |s|
          if s.salesforce_opportunity.nil? # CS Opportunity not linked to SFDC Opportunity
            if s.account.salesforce_accounts.present? # CS Opportunity linked to SFDC Account
              s.account.salesforce_accounts.each do |sfa|
                load_result = Activity.load_salesforce_activities(@client, s, sfa.salesforce_account_id, type="Account", filter_predicate_str)
                #puts "$$$(import_salesforce)$$$ load_result: #{load_result}"

                if load_result[:status] == "ERROR"
                  failure_method_location = "Activity.load_salesforce_activities()"
                  error_detail = "Error while attempting to load activity from Salesforce Account \"#{sfa.salesforce_account_name}\" (sfdc_id='#{sfa.salesforce_account_id}') to CS Opportunity \"#{s.name}\" (opportunity_id='#{s.id}').  #{ load_result[:result] } Details: #{ load_result[:detail] }"
                  render_internal_server_error(method_name, failure_method_location, error_detail)
                  return
                end
              end
            end
          else # CS Opportunity linked to SFDC Opportunity
            # Save at the Opportunity level
            load_result = Activity.load_salesforce_activities(@client, s, s.salesforce_opportunity.salesforce_opportunity_id, type="Opportunity", filter_predicate_str)

            if load_result[:status] == "ERROR"
              failure_method_location = "Activity.load_salesforce_activities()"
              error_detail = "Error while attempting to load activity from Salesforce Opportunity \"#{s.salesforce_opportunity.name}\" (sfdc_id='#{s.salesforce_opportunity.salesforce_opportunity_id}') to CS Opportunity \"#{s.name}\" (opportunity_id='#{s.id}').  #{ load_result[:result] } Details: #{ load_result[:detail] }"
              render_internal_server_error(method_name, failure_method_location, error_detail)
              return
            end
          end
        end
      else
        render_service_unavailable_error(method_name)
        return
      end
    # end when params[:entity_type] = "activities"
    else
      # Error: unsupported Salesforce entity type; do nothing
    end

    render :text => ' '
  end

  # Export CS Activity or Contacts into the mapped SFDC Account (or Opportunity)
  def export_salesforce
    case params[:entity_type]
    when "activities"
      # All CS Activities are exported into the remote SFDC Account (or Opportunity), depending on the (primary) mapping of a CS opportunity to a SFDC opportunity, or the implicit/explicit (secondary) opportunity mapping of a CS opportunity (through the CS account) mapped to a SFDC account.
      # Note: Ignores imported SFDC activity residing locally
      method_name = "export_salesforce#activities()"
      @opportunities = Project.visible_to_admin(current_user.organization_id).is_active.is_confirmed.includes(:salesforce_opportunity) # all mappings for this user's organization
      no_linked_sfdc = @opportunities.none?{ |o| o.salesforce_opportunity.present? || o.account.salesforce_accounts.present? }

      # Nothing to do if no opportunities or linked SFDC entities
      if @opportunities.blank? || no_linked_sfdc
        @client = nil
        render :text => ' ' 
        return 
      end

      @client = SalesforceService.connect_salesforce(current_user.organization_id)

      Activity.delete_cs_activities(@client) #clear all existing CS Activities in SFDC (accounts)

      unless @client.nil?  # unless connection error
        @opportunities.each do |s|
          if s.salesforce_opportunity.nil? # CS Opportunity not linked to SFDC Opportunity
            if s.account.salesforce_accounts.present? # CS Opportunity linked to SFDC Account
              s.account.salesforce_accounts.each do |sfa|
                export_result = Activity.export_cs_activities(@client, s, sfa.salesforce_account_id, "Account")

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
            export_result = Activity.export_cs_activities(@client, s, s.salesforce_opportunity.salesforce_opportunity_id, "Opportunity")

            if export_result[:status] == "ERROR"
              method_location = "Activity.export_cs_activities()"
              error_detail = "Error while attempting to export CS activity from CS Opportunity \"#{s.name}\" (opportunity_id='#{s.id}') to Salesforce Opportunity \"#{s.salesforce_opportunity.name}\" (sfdc_id='#{s.salesforce_opportunity.salesforce_opportunity_id}').  Details: #{ export_result[:detail] }"
              render_internal_server_error(method_name, method_location, error_detail)
              return
            end
          end
        end
      else
        render_service_unavailable_error(method_name)
        return
      end
    #end when params[:entity_type] = "activities"
    when "contacts"
      # Export local Contacts out to SFDC Accounts, depending on the explicit (primary) mapping of a CS account to SFDC Account (first one).
      method_name = "export_salesforce#contacts()"
      account_mapping = []
      accounts = Account.visible_to(current_user)
      accounts.each do |a|
        account_mapping << [a, a.salesforce_accounts.first] if a.salesforce_accounts.present?
      end

      unless account_mapping.empty?  # no visible or mapped accounts
        client = SalesforceService.connect_salesforce(current_user.organization_id)
        #client = nil #simulate connection error
        unless client.nil?  # unless SFDC connection error
          export_result_messages = []
          error_occurred = false
          account_mapping.each do |m|
            a = m[0]
            sfa = m[1]
            export_result = Contact.export_cs_contacts(client, a.id, sfa.salesforce_account_id)

            if export_result[:status] == "ERROR"
              error_detail = export_result[:detail]
              export_result_messages << { account: { name: a.name, id: a.id }, sfdc_account: { name: sfa.salesforce_account_name, id: sfa.salesforce_account_id }, status: export_result[:status], detail: error_detail }
              error_occurred = true
            else # SUCCESS
              # export_result_messages << { account: { name: a.name, id: a.id }, sfdc_account: { name: sfa.salesforce_account_name, id: sfa.salesforce_account_id }, status: export_result[:status], detail: [] } 
            end
          end
          puts "\n\n==> Export result messages: #{export_result_messages}\n\n"
          if error_occurred
            failure_method_location = "Contact.export_cs_contacts()"
            render_internal_server_error(method_name, failure_method_location, export_result_messages.map{ |m| "\t*'#{m[:account][:name]}'(#{m[:account][:id]}) -> (SFDC)'#{m[:sfdc_account][:name]}'(#{m[:sfdc_account][:id]}) = #{m[:status]}! detail: #{m[:detail]}" if m[:status] == "ERROR" }.join("\n\n"))
            return
          end
        else
          render_service_unavailable_error(method_name)
          return
        end
      end
    # end when params[:entity_type] = "contacts"
    else
      # Error: unsupported Salesforce entity type; do nothing
    end

    render :text => ' '
  end

  # Native CS fields are updated according to the explicit mapping of a field of a SFDC opportunity to the field of a CS opportunity, or a field of a SFDC account to a field of a CS account. 
  # Parameters:   params[:entity_type] - "accounts" or "projects" or "contacts".
  #               params[:field_type] - "standard" or "custom"
  # Note: While it is typical to have a 1:1 mapping between CS and SFDC entities, it is possible to have a 1:N mapping.  If multiple SFDC accounts are mapped to the same CS account, the first mapping found will be used for the update. If multiple SFDC opportunities are mapped to the same CS Opportunity, an update will be carried out for each mapping.
  def refresh_fields
    method_name = "refresh_fields()"
    if params[:entity_type] == "accounts"
      if params[:field_type] == "standard"
        account_standard_fields = EntityFieldsMetadatum.get_sfdc_fields_mapping_for(organization_id: current_user.organization_id, entity_type: EntityFieldsMetadatum::ENTITY_TYPE[:Account])
        #puts "account_standard_fields: #{account_standard_fields}"
      else
        account_custom_fields = CustomFieldsMetadatum.where("organization_id = ? AND entity_type = ? AND salesforce_field is not null", current_user.organization_id, CustomFieldsMetadatum.validate_and_return_entity_type(CustomFieldsMetadatum::ENTITY_TYPE[:Account], true))
      end

      unless (params[:field_type] == "standard" && account_standard_fields.empty?) || (params[:field_type] == "custom" && account_custom_fields.empty?) # Nothing to do if no mappings are found
        @client = SalesforceService.connect_salesforce(current_user.organization_id)
        #@client=nil # simulates a Salesforce connection error

        unless @client.nil?  # unless connection error
          accounts = Account.where("accounts.organization_id = ? and status = 'Active'", current_user.organization_id)

          if params[:field_type] == "standard"
            update_result = Account.update_fields_from_sfdc(client: @client, accounts: accounts, sfdc_fields_mapping: account_standard_fields)
            if update_result[:status] == "ERROR"
              method_location = "Account.update_fields_from_sfdc()"
              error_detail = "Error while attempting to load standard fields from Salesforce Accounts.  #{ update_result[:result] } Details: #{ update_result[:detail] }"
              render_internal_server_error(method_name, method_location, error_detail)
              return
            end
          else # params[:field_type] == "custom"
            accounts.each do |a|
              unless a.salesforce_accounts.first.nil? 
                #print "***** SFDC account:\"", a.salesforce_accounts.first.salesforce_account_name, "\" --> CS account:\"", a.name, "\" *****\n"
                load_result = Account.load_salesforce_fields(client: @client, account_id: a.id, sfdc_account_id: a.salesforce_accounts.first.salesforce_account_id, account_custom_fields: account_custom_fields)

                if load_result[:status] == "ERROR"
                  method_location = "Account.load_salesforce_fields()"
                  error_detail = "Error while attempting to load fields from Salesforce Account \"#{a.salesforce_accounts.first.salesforce_account_name}\" (sfdc_id='#{a.salesforce_accounts.first.salesforce_account_id}') to CS Account \"#{a.name}\" (account_id='#{a.id}').  #{ load_result[:result] } Details: #{ load_result[:detail] }"
                  render_internal_server_error(method_name, method_location, error_detail)
                  return
                end
              end
            end # End: accounts.each do |s|
          end
        else
          render_service_unavailable_error(method_name)
          return
        end
      end
    elsif params[:entity_type] == "projects"
      if params[:field_type] == "standard"
        opportunity_standard_fields = EntityFieldsMetadatum.get_sfdc_fields_mapping_for(organization_id: current_user.organization_id, entity_type: EntityFieldsMetadatum::ENTITY_TYPE[:Project])
        puts "opportunity_standard_fields: #{opportunity_standard_fields}"
      else
        opportunity_custom_fields = CustomFieldsMetadatum.where("organization_id = ? AND entity_type = ? AND salesforce_field is not null", current_user.organization_id, CustomFieldsMetadatum.validate_and_return_entity_type(CustomFieldsMetadatum::ENTITY_TYPE[:Project], true))
      end

      unless (params[:field_type] == "standard" && opportunity_standard_fields.empty?) || (params[:field_type] == "custom" && opportunity_custom_fields.empty?) # Nothing to do if no mappings are found
        @client = SalesforceService.connect_salesforce(current_user.organization_id)
        #@client=nil # simulates a Salesforce connection error

        unless @client.nil?  # unless connection error
          opportunities = Project.visible_to_admin(current_user.organization_id).is_active.is_confirmed.includes(:salesforce_opportunity)

          if params[:field_type] == "standard"
            update_result = Project.update_fields_from_sfdc(client: @client, opportunities: opportunities, sfdc_fields_mapping: opportunity_standard_fields)
            if update_result[:status] == "ERROR"
              method_location = "Project.update_fields_from_sfdc()"
              error_detail = "Error while attempting to load standard fields from Salesforce Opportunities.  #{ update_result[:result] } Details: #{ update_result[:detail] }"
              render_internal_server_error(method_name, method_location, error_detail)
              return
            end
          else # params[:field_type] == "custom"
            opportunities.each do |s|
              unless s.salesforce_opportunity.nil?
                #print "***** SFDC opportunity:\"", s.salesforce_opportunity.name, "\" --> CS opportunity:\"", s.name, "\" *****\n"
                load_result = Project.load_salesforce_fields(client: @client, project_id: s.id, sfdc_opportunity_id: s.salesforce_opportunity.salesforce_opportunity_id, opportunity_custom_fields: opportunity_custom_fields)

                if load_result[:status] == "ERROR"
                  method_location = "Project.load_salesforce_fields()"
                  error_detail = "Error while attempting to load fields from Salesforce Opportunity \"#{s.salesforce_opportunity.name}\" (sfdc_id='#{s.salesforce_opportunity.salesforce_opportunity_id}') to CS Opportunity \"#{s.name}\" (opportunity_id='#{s.id}').  #{ load_result[:result] } Details: #{ load_result[:detail] }"
                  render_internal_server_error(method_name, method_location, error_detail)
                  return
                end
              end
            end # End: opportunities.each do |s|
          end
        else
          render_service_unavailable_error(method_name)
          return
        end
      end
    elsif params[:entity_type] == "contacts" && params[:field_type] == "standard"
      puts "Standard #{params[:entity_type]} fields all the wayyyyy!!!"
    else
      puts "Invalid entity_type parameter passed to refresh_fields(). entity_type=#{params[:entity_type]}"
    end

    render :text => ' '
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
    # delete salesforce data
    # delete salesforce oauth_user
    SalesforceAccount.where(contextsmith_organization_id: current_user.organization_id).destroy_all   # will unlink all accounts for the Organization if somebody from the Organization d/c's from their SFDC account!
    salesforce_user = OauthUser.find_by(id: params[:id])
    if salesforce_user.present?
      salesforce_user.destroy
      # Unmap SFDC fields to standard fields
      current_user.organization.entity_fields_metadatum.each do |fm|
        fm.update(salesforce_field: nil)
      end
      # Unmap SFDC fields to custom fields
      current_user.organization.custom_fields_metadatum.each do |fm|
        fm.update(salesforce_field: nil)
      end
    end

    respond_to do |format|
      format.html { redirect_to(request.referer || settings_path) }
    end
  end

  # Gets Salesforce (custom) fields in the form of the following hash:
  #   :sfdc_account_fields -- a list of SFDC account field names mapped to the field labels (visible to the user) in the form of [["acctfield1name", "acctfield1label (acctfield1name)"], ["acctfield2name", "acctfield2label (acctfield2name)"], ...]
  #   :sfdc_account_fields_metadata -- a hash of SFDC account field names with metadata info in the form of {"acctfield1" => {type: acctfield1.type, custom: acctfield1.custom, updateable: acctfield1.updateable, nillable: acctfield1.nillable} }
  #   :sfdc_opportunity_fields -- a list of SFDC opportunity field names mapped to the field labels (visible to the user) in a similar to :sfdc_account_fields
  #   :sfdc_opportunity_fields_metadata -- similar to :sfdc_account_fields_metadata for sfdc_opportunity_fields
  #   :sfdc_contact_fields -- a list of SFDC contact field names mapped to the field labels (visible to the user) in a similar to :sfdc_account_fields
  #   :sfdc_contact_fields_metadata -- similar to :sfdc_account_fields_metadata for sfdc_contact_fields
  # Returns {} if there is no SFDC connection detected for this Organization, or if there was a SFDC connection error.
  def self.get_salesforce_fields(organization_id: , custom_fields_only: false)
    client = SalesforceService.connect_salesforce(organization_id)

    return {} if client.nil?

    sfdc_account_fields = {}
    sfdc_account_fields_metadata = {}
    sfdc_opportunity_fields = {}
    sfdc_opportunity_fields_metadata = {}
    sfdc_contact_fields = {}
    sfdc_contact_fields_metadata = {}

    entity_describe = client.describe('Account')
    entity_describe.fields.each do |f|
      sfdc_account_fields[f.name] = f.label + " (" + f.name + ")" if (!custom_fields_only or f.custom)
      metadata = {}
      metadata["type"] = f.type
      metadata["custom"] = f.custom
      metadata["updateable"] = f.updateable
      metadata["nillable"] = f.nillable
      sfdc_account_fields_metadata[f.name] = metadata
    end
    entity_describe = client.describe('Opportunity')
    entity_describe.fields.each do |f|
      sfdc_opportunity_fields[f.name] = f.label + " (" + f.name + ")" if (!custom_fields_only or f.custom)
      metadata = {}
      metadata["type"] = f.type
      metadata["custom"] = f.custom
      metadata["updateable"] = f.updateable
      metadata["nillable"] = f.nillable
      sfdc_opportunity_fields_metadata[f.name] = metadata
    end
    entity_describe = client.describe('Contact')
    entity_describe.fields.each do |f|
      sfdc_contact_fields[f.name] = f.label + " (" + f.name + ")" if (!custom_fields_only or f.custom)
      metadata = {}
      metadata["type"] = f.type
      metadata["custom"] = f.custom
      metadata["updateable"] = f.updateable
      metadata["nillable"] = f.nillable
      sfdc_contact_fields_metadata[f.name] = metadata
    end

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
    #@project_risk_score = @project.new_risk_score(current_user.time_zone)
    @project_open_risks_count = @project.notifications.open.alerts.count
    @project_pinned_count = @project.activities.pinned.visible_to(current_user.email).count
    @project_open_tasks_count = @project.notifications.open.count
    project_rag_score = @project.activities.latest_rag_score.first

    if project_rag_score
      @project_rag_status = project_rag_score['rag_score']
    end

    # old metrics
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

    # for merging projects/opportunities, for future use
    # @account_projects = @project.account.projects.where.not(id: @project.id).pluck(:id, :name)
  end

  def load_timeline
    activities = @project.activities.visible_to(current_user.email).includes(:notifications, :comments)
    # filter by categories
    @filter_category = []
    if params[:category].present?
      @filter_category = params[:category].split(',')
      activities = activities.where(category: @filter_category)
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

  def render_service_unavailable_error(method_name)
    puts "****SFDC****: Salesforce service unavailable in SalesforceController.#{method_name}: Cannot establish a connection!"
    render json: { error: "Salesforce service unavailable: cannot establish a connection" }, status: :service_unavailable #503
  end

  def render_internal_server_error(method_name, method_location, error_detail)
    puts "****SFDC****: Salesforce query error in SalesforceController.#{method_name} (#{method_location}): #{error_detail}"
    render json: { error: error_detail }, status: :internal_server_error # 500
  end
end
