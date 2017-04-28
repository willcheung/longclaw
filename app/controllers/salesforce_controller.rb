class SalesforceController < ApplicationController
  layout "empty", only: [:index]

  # For accessing Streams#show page+tabs from a Salesforce iframe "page"
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
      sf_account = SalesforceAccount.eager_load(:account).find_by(salesforce_account_id: @salesforce_id, contextsmith_organization_id: current_user.organization_id)
      return if sf_account.nil?  # invalid SFDC id or id cannot be found

      cs_account = sf_account.account
      return if cs_account.nil?  # no CS accounts mapped to this Salesforce account
    end

    @is_mapped_to_CS_account = true

    @actiontype = (params[:actiontype].present? && (["index", "show", "filter_timeline", "more_timeline", "pinned_tab", "tasks_tab", "insights_tab", "arg_tab"].include? params[:actiontype])) ? params[:actiontype] : 'show'

    # check if CS account_id is valid and in the scope
    @streams_mapped = Project.visible_to(current_user.organization_id, current_user.id).where(account_id: cs_account.id)
    #@streams_mapped.each { |p| puts "**************** project=#{ p.name }"}
    #puts ">>>>>>>>>>>>>>>>>>>>>>>>>>> cs_account.id=#{cs_account.id}"

    activities = []
    if @streams_mapped.present?
      if params[:pid].present?
        @project = @streams_mapped.detect {|p| p.id == params[:pid]} || nil
      else
        @project = @streams_mapped[0]
      end

      return if @project.blank?
      #puts ">>>>>>>>>>>> @project = #{@project.id}, #{@project.name}" 

      # Top status
      @project_risk_score = @project.new_risk_score(current_user.time_zone)
      @project_open_tasks_count = @project.notifications.open.count

      # Tab specific (directly copied from "projects_controller.rb")
      @users_reverse = get_current_org_users   # get_users_reverse
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
      elsif @actiontype == "insights_tab"
        @risk_score_trend = @project.new_risk_score_trend(current_user.time_zone)

        # Engagement Volume Chart
        @activities_moving_avg = @project.activities_moving_average(current_user.time_zone)
        @activities_by_category_date = @project.daily_activities_last_x_days(current_user.time_zone).group_by { |a| a.category }
        activity_engagement = @activities_by_category_date["Conversation"].map {|c| c.num_activities }.to_a

        # TODO: Generate data for Risk Volume Chart in SQL query
        # Risk Volume Chart
        risk_notifications = @project.notifications.risks.where(created_at: 14.days.ago.midnight..Time.current.midnight)
        risks_by_date = Array.new(14, 0)
        risk_notifications.each do |r|
          # risks_by_date based on number of days since 14 days ago
          day_index = r.created_at.to_date.mjd - 14.days.ago.midnight.to_date.mjd
          risks_by_date[day_index] += 1
        end

        @risk_activity_engagement = []
        risks_by_date.zip(activity_engagement).each do | a, b|
          if b == 0
            @risk_activity_engagement.push(0)
          else
            @risk_activity_engagement.push(a/b.to_f * 100)
          end
        end

        #Shows the total email usage report
        @in_outbound_report = User.total_team_usage_report([@project.account.id], current_user.organization.domain)
        @meeting_report = User.meeting_team_report([@project.account.id], @in_outbound_report['email'])
        
        # TODO: Modify query and method params for count_activities_by_user_flex to take project_ids instead of account_ids
        # Most Active Contributors & Activities By Team
        user_num_activities = User.count_activities_by_user_flex([@project.account.id], current_user.organization.domain)
        @team_leaderboard = []
        @activities_by_dept = Hash.new(0)
        activities_by_dept_total = 0
        user_num_activities.each do |u|
          user = User.find_by_email(u.email)
          u.email = get_full_name(user) if user
          @team_leaderboard << u
          dept = user.nil? || user.department.nil? ? '(unknown)' : user.department
          @activities_by_dept[dept] += u.inbound_count + u.outbound_count
          activities_by_dept_total += u.inbound_count + u.outbound_count
        end
        # Convert Activities By Team to %
        @activities_by_dept.each { |dept, count| @activities_by_dept[dept] = (count.to_f/activities_by_dept_total*100).round(1)  }
        # Only show top 5 for Most Active Contributors
        @team_leaderboard = @team_leaderboard[0...5]
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

  def link_salesforce_account
    # One CS Account can link to many Salesforce Accounts
    salesforce_account = SalesforceAccount.find_by(id: params[:salesforce_id], contextsmith_organization_id: current_user.organization_id)
    if !salesforce_account.nil?
      salesforce_account.account = Account.find_by_id(params[:account_id])
      salesforce_account.save
    end

    respond_to do |format|
      format.html { redirect_to URI.escape(request.referer, ".") }
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

  # Load SFDC Accounts or Opportunities into CS models, or Load SFDC Contacts into mapped CS Accounts
  def refresh_salesforce
    case params[:entity_type]
    when "accounts"
      SalesforceAccount.load_accounts(current_user.organization_id)
    when "opportunities"
      SalesforceOpportunity.load_opportunities(current_user.organization_id)
    when "contacts"
      # Load SFDC Contacts into CS Accounts, depending on the explicit (primary) mapping of a SFDC Account (first one) to a CS account.
      account_mapping = []
      method_name = "refresh_salesforce#contacts()"
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
            errors = Contact.load_salesforce_contacts(client, a.id, sfa.salesforce_account_id)

            unless errors.nil? # Salesforce query error occurred
              failure_method_location = "Contact.load_salesforce_contacts()"
              error_detail = "Error while attempting to load contacts from Salesforce Account \"#{sfa.salesforce_account_name}\" (sfdc_id='#{sfa.salesforce_account_id}') to CS Account \"#{a.name}\" (stream_id='#{a.id}').  Details: #{errors}"
              render_internal_server_error(method_name, failure_method_location, error_detail)
              return
            end
          end
        else
          render_service_unavailable_error(method_name)
          return
        end
      end
    when "activities"
      # Load SFDC Activities into CS Streams, depending on the explicit (primary) mapping of a SFDC opportunity to a CS stream, or the implicit (secondary) stream mapping of a SFDC account mapped to a CS account.
      # Note: Ignores exported CS data residing on SFDC
      method_name = "refresh_salesforce#activities()"
      filter_predicate_str = {}
      filter_predicate_str["entity"] = params[:entity_pred].strip
      filter_predicate_str["activityhistory"] = params[:activityhistory_pred].strip

      #puts "******************** #{method_name}  ...  filter_predicate_str=", filter_predicate_str
      @streams = Project.visible_to_admin(current_user.organization_id).is_active.is_confirmed.includes(:salesforce_opportunity) # all active projects because "admin" role can see everything
      @client = SalesforceService.connect_salesforce(current_user.organization_id)

      unless @client.nil?  # unless connection error
        @streams.each do |s|
          if s.salesforce_opportunity.nil? # Stream not linked to SFDC Opportunity
            if !s.account.salesforce_accounts.empty? # Stream linked to SFDC Account
              s.account.salesforce_accounts.each do |sfa|
                errors = Activity.load_salesforce_activities(@client, s, sfa.salesforce_account_id, type="Account", filter_predicate_str)

                unless errors.nil? # Salesforce query error occurred
                  failure_method_location = "Activity.load_salesforce_activities()"
                  error_detail = "Error while attempting to load activity from Salesforce Account \"#{sfa.salesforce_account_name}\" (sfdc_id='#{sfa.salesforce_account_id}') to CS Stream \"#{s.name}\" (stream_id='#{s.id}').  Details: #{errors}"
                  render_internal_server_error(method_name, failure_method_location, error_detail)
                  return
                end
              end
            end
          else # Stream linked to Opportunity
            # If Stream is linked in Opportunity, then save on Opportunity level
            errors = Activity.load_salesforce_activities(@client, s, s.salesforce_opportunity.salesforce_opportunity_id, type="Opportunity", filter_predicate_str)

            unless errors.nil? # Salesforce query error occurred
              failure_method_location = "Activity.load_salesforce_activities()"
              error_detail = "Error while attempting to load activity from Salesforce Opportunity \"#{s.salesforce_opportunity.name}\" (sfdc_id='#{s.salesforce_opportunity.salesforce_opportunity_id}') to CS Stream \"#{s.name}\" (stream_id='#{s.id}').  Details: #{errors}"
              render_internal_server_error(method_name, failure_method_location, error_detail)
              return
            end
          end
        end
      else
        render_service_unavailable_error(method_name)
        return
      end
    else
      # Error: unsupported Salesforce entity type
    end
    render :text => ' '
  end

  # CS Activities are exported into the remote SFDC Account (or Opportunity), depending on the (primary) mapping of a CS stream to a SFDC opportunity, or the implicit/explicit (secondary) stream mapping of a CS stream (through the CS account) mapped to a SFDC account.
  # Note: Ignores imported SFDC data residing locally
  def export_activities
    method_name = "export_activities()"

    @streams = Project.visible_to_admin(current_user.organization_id).is_active.is_confirmed.includes(:salesforce_opportunity) # all mappings for this user's organization

    @client = SalesforceService.connect_salesforce(current_user.organization_id)

    Activity.delete_cs_activities(@client) #clear all existing CS Activities in SFDC (accounts)

    unless @client.nil?  # unless connection error
      @streams.each do |s|
        if s.salesforce_opportunity.nil? # Stream not linked to SFDC Opportunity
          if !s.account.salesforce_accounts.empty? # Stream linked to SFDC Account
            s.account.salesforce_accounts.each do |sfa|
              errors = Activity.export_cs_activities(@client, s, sfa.salesforce_account_id, "Account")

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
          errors = Activity.export_cs_activities(@client, s, s.salesforce_opportunity.salesforce_opportunity_id, "Opportunity")

          unless errors.nil? # Salesforce query error occurred
            method_location = "Activity.export_cs_activities()"
            error_detail = "Error while attempting to export CS activity from CS Stream \"#{s.name}\" (stream_id='#{s.id}') to Salesforce Opportunity \"#{s.salesforce_opportunity.name}\" (sfdc_id='#{s.salesforce_opportunity.salesforce_opportunity_id}').  Details: #{errors}"
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

  # Native CS fields are refreshed/updated according to the explicit mapping of a SFDC opportunity to a CS stream, or a SFDC account to a CS account. 
  # Parameters: entity_type: = "accounts" or "projects".
  # Note: While it is typical to have a 1:1 mapping between CS and SFDC entities, it is possible to have a 1:N mapping.  If multiple SFDC accounts are mapped to the same CS account, the first mapping found will be used for the update. If multiple SFDC opportunities are mapped to the same CS stream, an update will be carried out for each mapping.
  def refresh_fields
    method_name = "refresh_fields()"
    if params[:entity_type] == "accounts"
      account_custom_fields = CustomFieldsMetadatum.where("organization_id = ? AND entity_type = ? AND salesforce_field is not null", current_user.organization_id, CustomFieldsMetadatum.validate_and_return_entity_type(CustomFieldsMetadatum::ENTITY_TYPE[:Account], true))

      unless account_custom_fields.empty? # Nothing to do if no custom fields or mappings are found
        @client = SalesforceService.connect_salesforce(current_user.organization_id)
        #@client=nil # simulates a Salesforce connection error

        unless @client.nil?  # unless connection error
          accounts = Account.where("accounts.organization_id = ? and status = 'Active'", current_user.organization_id)
          accounts.each do |a|
            unless a.salesforce_accounts.first.nil? 
              #print "***** SFDC account:\"", a.salesforce_accounts.first.salesforce_account_name, "\" --> CS account:\"", a.name, "\" *****\n"
              errors = Account.load_salesforce_fields(@client, a.id, a.salesforce_accounts.first.salesforce_account_id, account_custom_fields)
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
        @client = SalesforceService.connect_salesforce(current_user.organization_id)
        #@client=nil # simulates a Salesforce connection error

        unless @client.nil?  # unless connection error
          streams = Project.visible_to_admin(current_user.organization_id).is_active.is_confirmed.includes(:salesforce_opportunity)
          streams.each do |s|
            unless s.salesforce_opportunity.nil?
              #print "***** SFDC stream:\"", s.salesforce_opportunity.name, "\" --> CS opportunity:\"", s.name, "\" *****\n"
              errors = Project.load_salesforce_fields(@client, s.id, s.salesforce_opportunity.salesforce_opportunity_id, stream_custom_fields)
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
    salesforce_user.destroy if salesforce_user.present?

    respond_to do |format|
      format.html { redirect_to(request.referer || settings_path) }
    end
  end

  private

  def get_show_data
    # metrics
    @project_risk_score = @project.new_risk_score(current_user.time_zone)
    @project_open_risks_count = @project.notifications.open.risks.count
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

    # for merging projects, for future use
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
