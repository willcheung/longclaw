class ProjectsController < ApplicationController
  before_action :check_params_for_valid_dates, only: [:update]
  before_action :set_visible_project, only: [:show, :edit, :tasks_tab, :arg_tab, :lookup, :network_map, :refresh, :filter_timeline, :more_timeline]
  before_action :set_editable_project, only: [:destroy, :update]
  before_action :get_account_names, only: [:index, :new, :show, :edit] # So "edit" or "new" modal will display all accounts
  before_action :get_current_org_users, only: [:index, :show, :filter_timeline, :more_timeline, :tasks_tab, :arg_tab]
  before_action :get_current_org_opportunity_stages, only: [:show, :tasks_tab, :arg_tab]
  before_action :get_current_org_opportunity_forecast_categories, only: [:show, :tasks_tab, :arg_tab]
  before_action :get_show_data, only: [:show, :tasks_tab, :arg_tab]
  before_action :load_timeline, only: [:show, :filter_timeline, :more_timeline]
  before_action :get_custom_fields_and_lists, only: [:show, :tasks_tab, :arg_tab]
  before_action :project_filter_state, only: [:index]
  

  # GET /projects
  # GET /projects.jsonP
  def index
    respond_to do |format|
      format.html { index_html }
      format.json { render json: index_json }
    end
  end

  # GET /projects/1
  # GET /projects/1.json
  def show
    # get data for user filter
    @final_filter_user = @project.all_involved_people(current_user.email)
    # get data for time series filter
    @activities_by_category_date = @project.daily_activities(current_user.time_zone).group_by { |a| a.category }
    @pinned_activities = @project.activities.pinned.visible_to(current_user.email).reverse
    # get categories for category filter
    @categories = @activities_by_category_date.keys
    @categories << Activity::CATEGORY[:Pinned] if @pinned_activities.present?
    @ns_activity = @project.activities.where(category: Activity::CATEGORY[:NextSteps]).first
  end

  def filter_timeline
    respond_to :js
  end

  def more_timeline
    respond_to :js
  end

  def tasks_tab
    # show every risk regardless of private conversation
    @notifications = @project.notifications

    render "show"
  end

  def arg_tab # Account Relationship Graph
    @data = @project.activities.where(category: %w(Conversation Meeting)).ids
    @contacts = @project.contact_relationship_metrics

    render "show"
  end

  def network_map
    respond_to do |format|
      format.json { render json: @project.network_map }
    end
  end

  def lookup
    pinned = @project.conversations.pinned
    meetings = @project.meetings
    all_members = @project.project_members_all
    suggested_members = all_members.pending.map { |pm| pm.user_id || pm.contact_id }
    rejected_members = all_members.rejected.map { |pm| pm.user_id || pm.contact_id }
    members = (@project.users_all + @project.contacts_all).map do |m|
      next if rejected_members.include?(m.id)
      pin = pinned.select { |p| p.from.first.address == m.email || p.posted_by == m.id }
      meet = meetings.select { |p| p.from.first.address == m.email || p.posted_by == m.id }
      suggested = suggested_members.include?(m.id) ? ' *' : ''
      {
        name: get_full_name(m) + suggested,
        domain: get_domain(m.email),
        email: m.email,
        title: m.title,
        key_activities: pin.length,
        meetings: meet.length
      }
    end.compact
    respond_to do |format|
      format.json { render json: members }
    end
  end

  def refresh
    # big refresh when no activities (normally a new Opportunity), small refresh otherwise
    if @project.activities.count == 0
      puts "<><> Big asynchronous refresh incoming... <><>"
      ContextsmithService.load_emails_from_backend(@project, 2000)
      ContextsmithService.load_calendar_from_backend(@project, 1000)
      # 6.months.ago or more is too long ago, returns nil. 150.days is just less than 6.months and should work
    else
      ContextsmithService.load_emails_from_backend(@project)
      ContextsmithService.load_calendar_from_backend(@project, 100, 1.day.ago.to_i)
    end
    redirect_to :back
  end

  # GET /projects/new
  def new
    @project = Project.new
  end

  # GET /projects/1/edit
  def edit
  end

  # POST /projects
  # POST /projects.json
  def create
    @project = Project.new(project_params.merge(status: 'Active',
                                                owner_id: current_user.id,
                                                is_confirmed: true,
                                                created_by: current_user.id,
                                                updated_by: current_user.id
                                                ))
    # Add current_user to project member
    @project.project_members.new(user: current_user)
    # TODO: Uncomment below to undo #1011
    # Subscribe current_user as weekly / daily follower because s/he created the project
    # @project.subscribers.new(user: current_user)
    # Subscribe current_user as daily follower only temporarily (per #1011)
    @project.subscribers.new(user: current_user, weekly: false)

      respond_to do |format|
        if params[:commit] == 'Create with account contacts' 
          members = @project.account.contacts
            members.each do |input|
              new_member = @project.project_members.new(contact: input)
            end
          if @project.save
            # Big First Refresh, potentially won't need big refresh in the refresh method above
            ContextsmithService.load_emails_from_backend(@project, 2000)
            ContextsmithService.load_calendar_from_backend(@project, 1000)
            format.html { redirect_to @project, notice: 'Opportunity was successfully created.' }
            format.js
            #format.json { render action: 'show', status: :created, location: @project }
          else
            format.html { render action: 'new' }
            format.js { render json: @project.errors, status: :unprocessable_entity }
            #format.json { render json: @project.errors, status: :unprocessable_entity }
          end
        else  # params[:commit] == 'Blank Opportunity'
          if @project.save
            format.html { redirect_to @project, notice: 'Opportunity was successfully created.' }
            format.js
            #format.json { render action: 'show', status: :created, location: @project 
          else
            puts "Failure to save opportunity"
            format.html { render action: 'new' }
            format.js { render json: @project.errors, status: :unprocessable_entity }
            #format.json { render json: @project.errors, status: :unprocessable_entity }
          end
        end
      end 
  end

  # PATCH/PUT /projects/1
  # PATCH/PUT /projects/1.json
  def update
    if project_params['next_steps']
      @ns_updated = true
      @activity = @project.activities.create(
          category: Activity::CATEGORY[:NextSteps],
          # new next_steps stored in title
          title: project_params['next_steps'],
          # old next_steps stored in note
          note: @project.next_steps.blank? ? '(none)' : @project.next_steps,
          email_messages: [{ original_next_steps: @project.next_steps.blank? ? '(none)' : @project.next_steps, new_next_steps: project_params['next_steps'] }],
          posted_by: current_user.id,
          is_public: true,
          last_sent_date: Time.now,
          last_sent_date_epoch: Time.now.to_i
      )
    end

    respond_to do |format|
      if @project.update(project_params)
        format.html { redirect_to @project, notice: 'Project was successfully updated.' }
        format.js
        format.json { respond_with_bip(@project) }

        if @sfdc_client
          update_result = SalesforceOpportunity.update_all_salesforce(client: @sfdc_client, salesforce_opportunity: @project.salesforce_opportunity, fields: project_params, current_user: current_user) 
          puts "*** SFDC error: Error in ProjectsController.update during update of linked SFDC opportunity. Detail: #{update_result[:detail]} ***" if update_result[:status] == "ERROR" # TODO: Warn the user SFDC opp was not updated!
        end
      else
        format.html { render action: 'edit' }
        format.js { render json: @project.errors, status: :unprocessable_entity }
        format.json { render json: @project.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /projects/1
  # DELETE /projects/1.json
  def destroy
    @project.destroy
    respond_to do |format|
      format.html { redirect_to projects_url }
      format.js
      format.json { head :no_content }
    end
  end

  # Handle bulk operations
  def bulk
    render :json => { success: true }.to_json and return if params['project_ids'].blank?
    bulk_projects = Project.visible_to(current_user.organization_id, current_user.id).where(id: params['project_ids'])

    case params['operation']
    when 'delete'
      bulk_projects.destroy_all
    when 'category'
      bulk_projects.update_all(category: params['value'])
    when 'owner'
      bulk_projects.update_all(owner_id: params['value'])
    when 'status'
      bulk_projects.update_all(status: params['value'])
    else
      puts 'Invalid bulk operation, no operation performed'
    end

    render :json => {:success => true, :msg => ''}.to_json
  end

  private

  def index_html
    # puts "\n\n\t************ index_html *************\n"
    # puts "\tparams[:type]: #{params[:type]}"
    # puts "\tparams[:owner]: #{params[:owner]}"
    # puts "\tparams[:close_date]: #{params[:close_date]}"
    # puts "\tparams[:stage]: #{params[:stage]}"
    # puts "\n\n" 

    get_custom_fields_and_lists
    @owners = User.registered.where(organization_id: current_user.organization_id).ordered_by_first_name
    @project = Project.new
    projects = Project.visible_to(current_user.organization_id, current_user.id)

    # Incrementally apply filters to determine the projects to be used in the Stage filter
    params[:close_date] = Project::CLOSE_DATE_RANGE[:ThisQuarter] if params[:close_date].blank?
    projects = projects.close_date_within(params[:close_date]) unless params[:close_date] == 'Any'

    if params[:owner].present? && (!params[:owner].include? "0")
      if (!params[:owner].include? "None")
        projects = projects.where(owner_id: params[:owner])
      else
        projects = projects.where("\"projects\".owner_id IS NULL OR \"projects\".owner_id IN (?)", params[:owner].select{|o| o != "None"})
      end
    end

    if params[:type].present? && (!params[:type].include? "0")
      projects = projects.where(category: params[:type])
    end

    set_top_dashboard_data(project_ids: projects.ids)
    @no_progress = true
  end

  def index_json
    # @MEMBERS_LIST_LIMIT = 8 # Max number of Opportunity members to show in mouse-over tooltip

    # puts "\n\n\t************ index_json *************\n"
    # puts "\tparams[:type]: #{params[:type]}"
    # puts "\tparams[:owner]: #{params[:owner]}"
    # puts "\tparams[:close_date]: #{params[:close_date]}"
    # puts "\tparams[:stage]: #{params[:stage]}"
    # puts "\n\n"

    # Get an initial list of visible projects
    projects = Project.visible_to(current_user.organization_id, current_user.id)

    total_records = projects.ids.size

    # params[:close_date] = Project::CLOSE_DATE_RANGE[:ThisQuarter] if params[:close_date].blank?
    projects = projects.close_date_within(params[:close_date]) unless params[:close_date] == 'Any'

    if params[:owner].present? && (!params[:owner].include? "0")
      if (!params[:owner].include? "None")
        projects = projects.where(owner_id: params[:owner])
      else
        projects = projects.where("\"projects\".owner_id IS NULL OR \"projects\".owner_id IN (?)", params[:owner].select{|o| o != "None"})
      end
    end

    projects = projects.where(category: params[:type]) if params[:type].present? && (!params[:type].include? "0")
    projects = projects.where(stage: params[:stage]) if params[:stage].present? && (!params[:stage].include? "Any")
    projects = projects.where(forecast: params[:forecast]) if params[:forecast].present? && (!params[:forecast].include? "Any")

    # searching
    projects = projects.where('LOWER(projects.name) LIKE LOWER(:search) OR LOWER(projects.stage) LIKE LOWER(:search) OR LOWER(projects.forecast) LIKE LOWER(:search)', search: "%#{params[:sSearch]}%") if params[:sSearch].present?

    # ordering
    columns = [nil, 'name', 'stage', 'amount', 'forecast']
    column_is_text = [false, true, true, false, true]
    sort_by = columns[params[:iSortCol_0].to_i]
    sql_fn = column_is_text[params[:iSortCol_0].to_i] ? "LOWER" : ""
    projects = projects.select("#{sql_fn}(projects.#{sort_by})").order("#{sql_fn}(projects.#{sort_by}) #{params[:sSortDir_0]} NULLS LAST")

    # PAGINATE HERE
    total_display_records = projects.ids.size
    per_page = params[:iDisplayLength].to_i > 0 ? params[:iDisplayLength].to_i : 10
    page = params[:iDisplayStart].to_i/per_page
    projects = projects.limit(per_page).offset(per_page * page)

    unless projects.empty?
      @project_days_inactive = projects.joins(:activities).where.not(activities: { category: [Activity::CATEGORY[:Note], Activity::CATEGORY[:Alert], Activity::CATEGORY[:NextSteps]] }).where('activities.last_sent_date <= ?', Time.current).maximum("activities.last_sent_date") # get last_sent_date
      @project_days_inactive.each { |pid, last_sent_date| @project_days_inactive[pid] = Time.current.to_date.mjd - last_sent_date.in_time_zone.to_date.mjd } # convert last_sent_date to days inactive
      @sparkline = Project.count_activities_by_day_sparkline(projects.ids, current_user.time_zone)
      # @days_to_close = Project.days_to_close(projects.ids)
      @open_risk_count = Project.open_risk_count(projects.ids)
      #@risk_scores = Project.new_risk_score(projects.ids, current_user.time_zone)
      @next_meetings = Activity.meetings.next_week.select("project_id, min(last_sent_date) as next_meeting").where(project_id: projects.ids).group("project_id")
      @next_meetings = Hash[@next_meetings.map { |p| [p.project_id, p.next_meeting] }]
    end

    # all projects and their accounts, sorted by account name alphabetically
    @projects = projects.preload([:users,:contacts,:subscribers,:account]).select("project_subscribers.daily, project_subscribers.weekly").joins("LEFT OUTER JOIN project_subscribers ON project_subscribers.project_id = projects.id AND project_subscribers.user_id = '#{current_user.id}'").group("project_subscribers.id") #.group_by{|e| e.account}.sort_by{|account| account[0].name}

    vc = view_context

    {
      sEcho: params[:sEcho].to_i,
      iTotalRecords: total_records,
      iTotalDisplayRecords: total_display_records,
      aaData: @projects.map do |project|
        all_members = project.users.count + project.contacts.count
        members_html = "<span><i class=\"fa fa-users\" style=\"color:#888\"></i> #{all_members}</span>"
        ns_activity = project.activities.where(category: Activity::CATEGORY[:NextSteps]).first
        ns_updated_at = ns_activity.blank? ? '' : '<p class="m-b-none"><small class="text-muted">Updated '.html_safe + vc.time_ago_in_words(ns_activity.last_sent_date.in_time_zone(current_user.time_zone)) + ' ago</small></p>'.html_safe
        close_date_html = "<span #{'class="text-danger"' if project.close_date.present? && project.close_date < Time.current} title='#{project.close_date if project.close_date.present?}'>#{project.close_date.present? ? project.close_date.strftime('%b %-d') : '-'}</span>"
        [
          ("<input type=\"checkbox\" class=\"bulk-project\" value=\"#{project.id}\">" if current_user.admin?),
          vc.link_to(project.name, project) + '<br><small>'.html_safe + vc.link_to(project.account.name, project.account, class: 'link-muted') + '</small>'.html_safe,
          (project.stage.blank? ? "-" : project.stage),
          (project.amount.nil?) ? "-" : "$"+vc.number_to_human(project.amount),
          (project.forecast.blank? ? '-' : project.forecast),
          get_full_name(project.project_owner),
          members_html,
          vc.simple_format(vc.truncate(vc.word_wrap(CGI.escape_html(project.next_steps.blank? ? '(none)' : project.next_steps)), length: 300, separator: '\n') ) + ns_updated_at, # pass next steps to dataTables as hidden column, use word_wrap + truncate to ensure only 2 lines shown TODO: implement show more link
          @next_meetings[project.id].nil? ? "-" : @next_meetings[project.id].in_time_zone(current_user.time_zone).strftime('%b %-d (%a) %l:%M%P'),
          close_date_html,
          "<span class='#{@open_risk_count[project.id].present? && @open_risk_count[project.id] > 0 ? 'text-danger' : ''}'>#{@open_risk_count[project.id].to_s}</span>",
          "<div data-sparkline=\"#{@sparkline[project.id].join(', ') if @sparkline[project.id].present?}; column\"></div>",
          @project_days_inactive[project.id].nil? ? "-" : @project_days_inactive[project.id],
          project.daily ? vc.link_to("<i class=\"fa fa-check\"></i> Daily".html_safe, project_project_subscriber_path(project_id: project.id, user_id: current_user.id) + "?type=daily", remote: true, method: :delete, id: "project-index-unfollow-daily-#{project.id}", class: "block m-b-xs", title: "Following daily") : vc.link_to("<i class=\"fa fa-bell-o\"></i> Daily".html_safe, project_project_subscribers_path(project_id: project.id, user_id: current_user.id) + "&type=daily", remote: true, method: :post, id: "project-index-follow-daily-#{project.id}", class: "block m-b-xs", title: "Follow daily")
        ]
      end
    }
  end

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
      where_email_clause = @filter_email.map { |e| "\"from\" || \"to\" || \"cc\" @> '[{\"address\":\"#{e}\"}]'::jsonb" }.join(' OR ')
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

  # Use callbacks to share common setup or constraints between actions.
  def set_visible_project
    @project = Project.visible_to(current_user.organization_id, current_user.id).find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to root_url, :flash => { :error => "Project not found or is private." }
  end

  # Should we re-use Project.visible_to scope?
  def set_editable_project
    @project = Project.joins(:account)
                      .where('accounts.organization_id = ?
                              AND (projects.is_public=true
                                    OR (projects.is_public=false AND projects.owner_id = ?) OR ?)', current_user.organization_id, current_user.id, current_user.admin?)
                      .find(params[:id])
    if (@project.present? && @project.is_linked_to_SFDC?)
      sfdc_oauthuser = SalesforceController.get_sfdc_oauthuser(user: current_user) || SalesforceController.get_sfdc_oauthuser(organization: current_user.organization)  # Use current user's SFDC login/connection if available; otherwise, use admin's SFDC login/connection regardless of current user's role
      
      @sfdc_client = SalesforceService.connect_salesforce(sfdc_oauthuser: sfdc_oauthuser) if sfdc_oauthuser.present?

      puts "****SFDC**** Warning: no SFDC connection is available or can be established. Linked Salesforce opportunity was not updated!" if @sfdc_client.nil? # TODO: Issue a warning to the user that the linked SFDC opp was not updated!
    end
  rescue ActiveRecord::RecordNotFound
    redirect_to root_url, :flash => { :error => "Project not found or is private." }
  end

  def get_account_names
    @account_names = Account.all.select('name', 'id').where("accounts.organization_id = ?", current_user.organization_id).references(:account).order('LOWER(name)')
  end

  # Never trust parameters from the scary internet, only allow the white list through.
  def project_params
    params.require(:project).permit(:name, :description, :is_public, :account_id, :owner_id, :category, :renewal_date, :contract_start_date, :contract_end_date, :contract_arr, :renewal_count, :has_case_study, :is_referenceable, :amount, :stage, :close_date, :expected_revenue, :probability, :forecast, :next_steps)
  end

  # A list of the param names that can be used for filtering the Project list
  def filtering_params(params)
    params.slice(:status, :location, :starts_with)
  end

  def get_custom_fields_and_lists
    @custom_lists = current_user.organization.get_custom_lists_with_options
    @opportunity_types = !@custom_lists.blank? ? @custom_lists["Opportunity Type"] : {}
  end

  def project_filter_state
    if params[:type]
      cookies[:project_type] = {value: params[:type]}
    else
      params[:type] = cookies[:project_type].present? ? cookies[:project_type].split("&") : []
    end
    if params[:owner]
      cookies[:project_owner] = {value: params[:owner]}
    else
      params[:owner] = cookies[:project_owner].present? ? cookies[:project_owner].split("&") : []
    end
    if params[:stage]
      cookies[:project_stage] = {value: params[:stage]}
    else
      params[:stage] = cookies[:project_stage].present? ? cookies[:project_stage].split("&") : []
    end
    if params[:forecast]
      cookies[:project_forecast] = {value: params[:forecast]}
    else
      params[:forecast] = cookies[:project_forecast].present? ? cookies[:project_forecast].split("&") : []
    end
    # Default is always "This Quarter"
    # if params[:close_date]
    #   cookies[:project_close_date] = {value: params[:close_date]}
    # else
    #   if cookies[:project_close_date]
    #     params[:close_date] = cookies[:project_close_date]
    #   end
    # end
  end
  # Allows smooth update of close_date and renewal_date using jQuery Datepicker widget.  In particular because of an different/incompatible Date format sent by widget to this controller to update a field of a non-timestamp (simple Date) type.
  def check_params_for_valid_dates
    params["project"][:close_date] = parse_date(params["project"][:close_date]) if params["project"][:close_date].present?
    params["project"][:renewal_date] = parse_date(params["project"][:renewal_date]) if params["project"][:renewal_date].present?
  end
end
