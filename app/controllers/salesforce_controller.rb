class SalesforceController < ApplicationController
  layout "empty", only: [:index]

  def index
    @category_param = []
    @filter_email = []

    @projects = []
    @activities_by_month = []
    @activities_by_date = []
    @project = Project.new
    @isconnect = false

    @actiontype = 'show'
    @pinned_activities = []
    @data = []

    if params[:id].nil?
      return
    else
      # set this salesforce id to contextsmith account id
      @salesforce_id = params[:id]

      salesforce = SalesforceAccount.eager_load(:account).find_by(salesforce_account_id: params[:id], contextsmith_organization_id: current_user.organization_id)

      if salesforce.nil?
        return
      end

      account = salesforce.account
      if account.nil?
        return
      end
    end

    if !params[:actiontype].nil?
      @actiontype = params[:actiontype]
    end

    @isconnect = true

    # check if id is valid and in the scope

    # for now, just use test account
    @projects = Project.includes(:activities).where(account_id: account.id)
    activities = []
    if !@projects.empty?
      if !params[:pid].nil?
        @projects.each do |p|
          if p.id == params[:pid]
            @final_filter_user = p.all_involved_people(current_user.email)
            activities = Activity.get_activity_by_filter(p, params)
            @project_risk_score = p.current_risk_score(current_user.time_zone)
            @project = p
          end
        end
      else
        @final_filter_user = @projects[0].all_involved_people(current_user.email)
        activities = Activity.get_activity_by_filter(@projects[0], params)

        @project_risk_score = @projects[0].current_risk_score(current_user.time_zone)
        @project = @projects[0]
      end
      @activities_by_month = activities.select {|a| a.is_visible_to(current_user) }.group_by {|a| a.last_sent_date.strftime('%^B %Y') }
      activities_by_date_temp = activities.select {|a| a.is_visible_to(current_user) }.group_by {|a| a.last_sent_date.strftime('%Y %m %d') }

      activities_by_date_temp.each do |date, activities|
        temp = Struct.new(:utc_milli_timestamp, :count).new
        temp.utc_milli_timestamp = DateTime.strptime(date, '%Y %m %d').to_i * 1000
        temp.count = activities.length
        @activities_by_date.push(temp)
      end
      @activities_by_date = @activities_by_date.sort {|x, y| y.utc_milli_timestamp <=> x.utc_milli_timestamp }.reverse!

      @project_last_activity_date = @project.activities.where(category: "Conversation").maximum("activities.last_sent_date")
      project_last_touch = @project.activities.find_by(category: "Conversation", last_sent_date: @project_last_activity_date)
      @project_last_touch_by = project_last_touch ? project_last_touch.from[0].personal : "--"
      @project_open_risks_count = @project.notifications.open.risks.count
      @notifications = @project.notifications.order(:is_complete, :original_due_date)

      @pinned_activities = @project.activities.pinned.includes(:comments)
      # filter out not visible items
      @pinned_activities = @pinned_activities.select {|a| a.is_visible_to(current_user) }

      @data = @project.activities.where(category: %w(Conversation Meeting))

      @project_open_tasks_count = @project.notifications.open.count
      @project_pinned_count = @project.activities.pinned.count

      @users_reverse = get_current_org_users
    end

    if(!params[:category].nil? and !params[:category].empty?)
      @category_param = params[:category].split(',')
    end

    if(!params[:emails].nil? and !params[:emails].empty?)
      @filter_email = params[:emails].split(',')
    end
  end

  def link_salesforce_account
    # One CS Account can link to many Salesforce Accounts
    salesforce_account = SalesforceAccount.find_by(id: params[:salesforce_id], contextsmith_organization_id: current_user.organization_id)
    if !salesforce_account.nil?
      salesforce_account.account = Account.find_by_id(params[:account_id])
      salesforce_account.save
    end

    respond_to do |format|
      format.html { redirect_to settings_salesforce_path }
    end
  end

  def link_salesforce_opportunity
    # One CS Stream can link to many Salesforce Opportunities
    salesforce_opp = SalesforceOpportunity.find_by(id: params[:salesforce_id])
    if !salesforce_opp.nil?
      salesforce_opp.project = Project.find_by_id(params[:project_id])
      salesforce_opp.save
    end

    respond_to do |format|
      format.html { redirect_to settings_salesforce_opportunities_path }
    end
  end

  def refresh_accounts
    SalesforceAccount.load(current_user.organization_id)
    render :text => ' '
  end

  def refresh_opportunities
    SalesforceOpportunity.load(current_user.organization_id)
    render :text => ' '
  end

  # Activities are loaded into native CS Streams, depending on the explicit (primary) mapping of a SFDC opportunity to a CS stream, or the implicit (secondary) stream mapping of a SFDC account mapped to a CS account.
  def refresh_cs_activities
    method_name = "refresh_cs_activities()"
    filter_predicate_str = {}
    filter_predicate_str["entity"] = params[:entity_pred].strip
    filter_predicate_str["activityhistory"] = params[:activityhistory_pred].strip

    #puts "******************** #{method_name}  ...  filter_predicate_str=", filter_predicate_str
    @streams = Project.visible_to_admin(current_user.organization_id).is_active.is_confirmed.includes(:salesforce_opportunity) # all active projects because "admin" role can see everything

    client = SalesforceService.connect_salesforce(current_user.organization_id)

    unless client.nil?  # unless connection error
      @streams.each do |s|
        if s.salesforce_opportunity.nil? # Stream not linked to SFDC Opportunity
          if !s.account.salesforce_accounts.empty? # Stream linked to SFDC Account
            s.account.salesforce_accounts.each do |sfa|
              errors = Activity.load_salesforce_activities(client, s, sfa.salesforce_account_id, type="Account", filter_predicate_str)

              unless errors.nil? # Salesforce query error occurred
                method_location = "Activity.load_salesforce_activities()"
                error_detail = "Error while attempting to load activity from Salesforce Account \"#{sfa.salesforce_account_name}\" (sfdc_id='#{sfa.salesforce_account_id}') to CS Stream \"#{s.name}\" (stream_id='#{s.id}').  Details: #{errors}"
                render_internal_server_error(method_name, method_location, error_detail)
                return
              end
            end
          end
        else # Stream linked to Opportunity
          # If Stream is linked in Opportunity, then save on Opportunity level
          errors = Activity.load_salesforce_activities(client, s, s.salesforce_opportunity.salesforce_opportunity_id, type="Opportunity", filter_predicate_str)

          unless errors.nil? # Salesforce query error occurred
            method_location = "Activity.load_salesforce_activities()"
            error_detail = "Error while attempting to load activity from Salesforce Opportunity \"#{s.salesforce_opportunity.name}\" (sfdc_id='#{s.salesforce_opportunity.salesforce_opportunity_id}') to CS Stream \"#{s.name}\" (stream_id='#{s.id}').  Details: #{errors}"
            render_internal_server_error(method_name, method_location, error_detail)
            return
          end
        end
      end
    else
      render_service_unavailable_error(method_name)
      return
    end

    render :text => ' '
  end

  # Activities are exported into remote SFDC Account (or Opportunity), depending on the explicit (primary) mapping of a SFDC opportunity to a CS stream, or the implicit (secondary) stream mapping of a SFDC account mapped to a CS account.
  def export_cs_activities
    method_name = "export_cs_activities()"

    @streams = Project.visible_to_admin(current_user.organization_id).is_active.is_confirmed.includes(:salesforce_opportunity) # all active projects because "admin" role can see everything

    client = SalesforceService.connect_salesforce(current_user.organization_id)

    unless client.nil?  # unless connection error
      

      @streams.each do |s|
        if s.salesforce_opportunity.nil? # Stream not linked to SFDC Opportunity
          if !s.account.salesforce_accounts.empty? # Stream linked to SFDC Account
            s.account.salesforce_accounts.each do |sfa|
              #errors = Activity.export_cs_activities(client, s, sfa.salesforce_account_id, "Account")
              errors = Activity.export_cs_activities(client, s, "0013600000G3aLwAAJ", "Account")

              unless errors.nil? # Salesforce query error occurred
                method_location = "Activity.export_cs_activities()"
                error_detail = "Error while attempting to export CS activity from CS Stream \"#{s.name}\" (stream_id='#{s.id}') to Salesforce Account \"#{sfa.salesforce_account_name}\" (sfdc_id='#{sfa.salesforce_account_id}').  Details: #{errors}"
                render_internal_server_error(method_name, method_location, error_detail)
                return
              end
            end
          end
        else # Stream linked to Opportunity
          # If Stream is linked in Opportunity, then save on Opportunity level
=begin
          errors = Activity.export_cs_activities(client, s, s.salesforce_opportunity.salesforce_opportunity_id, "Opportunity")

          unless errors.nil? # Salesforce query error occurred
            method_location = "Activity.export_cs_activities()"
            error_detail = "Error while attempting to load activity from Salesforce Opportunity \"#{s.salesforce_opportunity.name}\" (sfdc_id='#{s.salesforce_opportunity.salesforce_opportunity_id}') to CS Stream \"#{s.name}\" (stream_id='#{s.id}').  Details: #{errors}"
            render_internal_server_error(method_name, method_location, error_detail)
            return
          end
=end
        end
      end
    else
      render_service_unavailable_error(method_name)
      return
    end

    render :text => ' '
  end

  # Native CS fields are refreshed/updated according to the explicit mapping of a SFDC opportunity to a CS stream, or a SFDC account to a CS account. 
  # Parameters: entity_type: = "accounts" or "projects".
  # Note: While it is typical to have a 1:1 mapping between CS and SFDC entities, it is possible to have a 1:N mapping.  If multiple SFDC accounts are mapped to the same CS account, the first mapping found will be used for the update. If multiple SFDC opportunities are mapped to the same CS stream, an update will be carried out for each mapping.
  def refresh_fields
    method_name = "refresh_fields()"
    if params[:entity_type] == "accounts"
      account_custom_fields = CustomFieldsMetadatum.where("organization_id = ? AND entity_type = ? AND salesforce_field is not null", current_user.organization_id, CustomFieldsMetadatum.validate_and_return_entity_type(CustomFieldsMetadatum::ENTITY_TYPE[:Account], true))

      unless account_custom_fields.empty? # Nothing to do if no custom fields or mappings are found
        client = SalesforceService.connect_salesforce(current_user.organization_id)
        #client=nil # simulates a Salesforce connection error

        unless client.nil?  # unless connection error
          accounts = Account.where("accounts.organization_id = ? and status = 'Active'", current_user.organization_id)
          accounts.each do |a|
            unless a.salesforce_accounts.first.nil? 
              #print "***** SFDC account:\"", a.salesforce_accounts.first.salesforce_account_name, "\" --> CS account:\"", a.name, "\" *****\n"
              errors = Account.load_salesforce_fields(client, a.id, a.salesforce_accounts.first.salesforce_account_id, account_custom_fields)
              #errors="This is a test error!!!" # simulates a Salesforce query error

              unless errors.nil? # Salesforce query error occurred
                method_location = "Account.load_salesforce_fields()"
                error_detail = "Error while attempting to load fields from Salesforce Account \"#{a.salesforce_accounts.first.salesforce_account_name}\" (sfdc_id='#{a.salesforce_accounts.first.salesforce_account_id}') to CS Account \"#{a.name}\" (account_id='#{a.id}').  Details: #{errors}"
                render_internal_server_error(method_name, method_location, error_detail)
                return
              end
            end
          end
        else
          render_service_unavailable_error(method_name)
          return
        end
      end
    elsif params[:entity_type] == "projects"
      stream_custom_fields = CustomFieldsMetadatum.where("organization_id = ? AND entity_type = ? AND salesforce_field is not null", current_user.organization_id, CustomFieldsMetadatum.validate_and_return_entity_type(CustomFieldsMetadatum::ENTITY_TYPE[:Project], true))

      unless stream_custom_fields.empty? # Nothing to do if no custom fields or mappings are found
        client = SalesforceService.connect_salesforce(current_user.organization_id)
        #client=nil # simulates a Salesforce connection error

        unless client.nil?  # unless connection error
          streams = Project.visible_to_admin(current_user.organization_id).is_active.is_confirmed.includes(:salesforce_opportunity)
          streams.each do |s|
            unless s.salesforce_opportunity.nil?
              #print "***** SFDC stream:\"", s.salesforce_opportunity.name, "\" --> CS opportunity:\"", s.name, "\" *****\n"
              errors = Project.load_salesforce_fields(client, s.id, s.salesforce_opportunity.salesforce_opportunity_id, stream_custom_fields)
              #errors="This is a test error!!!" # simulates a Salesforce query error

              unless errors.nil? # Salesforce query error occurred
                method_location = "Project.load_salesforce_fields()"
                error_detail = "Error while attempting to load fields from Salesforce Opportunity \"#{s.salesforce_opportunity.name}\" (sfdc_id='#{s.salesforce_opportunity.salesforce_opportunity_id}') to CS Stream \"#{s.name}\" (stream_id='#{s.id}').  Details: #{errors}"
                render_internal_server_error(method_name, method_location, error_detail)
                return
              end
            end
          end
        else
          render_service_unavailable_error(method_name)
          return
        end
      end
    else
      print "Invalid parameter passed to refresh_fields().  entity_type=", params[:entity_type], "!\n"
    end

    render :text => ' '
  end

  # Returns a hash of:
  # :sf_account_fields -- a list of SFDC account field names mapped to the field labels (visible to the user) in the form of [["acctfield1name", "acctfield1label (acctfield1name)"], ["acctfield2name", "acctfield2label (acctfield2name)"], ...]
  # :sf_account_fields_metadata -- a hash of SFDC account field names with metadata info in the form of {"acctfield1" => {type: acctfield1.type, custom: acctfield1.custom, updateable: acctfield1.updateable, nillable: acctfield1.nillable} }
  # :sf_opportunity_fields -- a list of SFDC opportunity field names mapped to the field labels (visible to the user) in a similar to :sf_account_fields
  # :sf_opportunity_fields_metadata -- similar to :sf_account_fields_metadata for sf_opportunity_fields
  def self.get_salesforce_fields(organization_id, custom_fields_only=false)
    client = SalesforceService.connect_salesforce(organization_id)

    return nil if client.nil?

    sf_account_fields = {}
    sf_account_fields_metadata = {}
    sf_opportunity_fields = {}
    sf_opportunity_fields_metadata = {}

    account_describe = client.describe('Account')
    account_describe.fields.each do |f|
      sf_account_fields[f.name] = f.label + " (" + f.name + ")" if (!custom_fields_only or f.custom)
      metadata = {}
      metadata["type"] = f.type
      metadata["custom"] = f.custom
      metadata["updateable"] = f.updateable
      metadata["nillable"] = f.nillable
      sf_account_fields_metadata[f.name] = metadata
    end
    account_describe = client.describe('Opportunity')
    account_describe.fields.each do |f|
      sf_opportunity_fields[f.name] = f.label + " (" + f.name + ")" if (!custom_fields_only or f.custom)
      metadata = {}
      metadata["type"] = f.type
      metadata["custom"] = f.custom
      metadata["updateable"] = f.updateable
      metadata["nillable"] = f.nillable
      sf_opportunity_fields_metadata[f.name] = metadata
    end

    sf_account_fields = sf_account_fields.sort_by { |k,v| v.upcase }
    sf_opportunity_fields = sf_opportunity_fields.sort_by { |k,v| v.upcase }

    return {sf_account_fields: sf_account_fields, sf_account_fields_metadata: sf_account_fields_metadata, sf_opportunity_fields: sf_opportunity_fields, sf_opportunity_fields_metadata: sf_opportunity_fields_metadata}
  end

  def remove_account_link
    salesforce_account = SalesforceAccount.eager_load(:account).find_by(id: params[:id], contextsmith_organization_id: current_user.organization_id)

    if !salesforce_account.nil?
      salesforce_account.salesforce_opportunities.destroy_all
      salesforce_account.contextsmith_account_id = nil
      salesforce_account.save
    end

    respond_to do |format|
      format.html { redirect_to settings_salesforce_path }
    end

  end

  def remove_opportunity_link
    salesforce_opp = SalesforceOpportunity.find_by(id: params[:id])

    if !salesforce_opp.nil?
      salesforce_opp.contextsmith_project_id = nil
      salesforce_opp.save
    end

    respond_to do |format|
      format.html { redirect_to settings_salesforce_opportunities_path }
    end

  end

  def disconnect
    # delete salesforce data
    # delete salesforce oauth_user
    SalesforceAccount.where(contextsmith_organization_id: current_user.organization_id).destroy_all
    salesforce_user = OauthUser.find_by(id: params[:id])
    salesforce_user.destroy

    respond_to do |format|
      format.html { redirect_to settings_salesforce_path }
    end
  end

  private

  def render_service_unavailable_error(method_name)
    puts "****SFDC****: Salesforce service unavailable in SalesforceController.#{method_name}: Cannot establish a connection!"
    render json: { error: "Salesforce service unavailable: cannot establish a connection" }, status: :service_unavailable #503
  end

  def render_internal_server_error(method_name, method_location, error_detail)
    puts "****SFDC****: Salesforce query error in SalesforceController.#{method_name} (#{method_location}): #{error_detail}"
    render json: { error: error_detail }, status: :internal_server_error # 500
  end
end
