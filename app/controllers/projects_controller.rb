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
  # GET /projects.json
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
    suggested_members = @project.project_members_all.pending.map { |pm| pm.user_id || pm.contact_id }
    members = (@project.users_all + @project.contacts_all).map do |m|
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
    end
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
    respond_to do |format|
      if @project.update(project_params)
        format.html { redirect_to @project, notice: 'Project was successfully updated.' }
        format.js
        format.json { respond_with_bip(@project) }

        if @project.salesforce_opportunity.present?
          update_result = SalesforceOpportunity.update_all_salesforce(client: @sfdc_client, salesforce_opportunity: @project.salesforce_opportunity, fields: project_params, current_user: current_user) 
          puts "*** SFDC error: Update SFDC opportunity error! Detail: #{update_result[:detail]} ***" if update_result[:status] == "ERROR" # TODO: Warn user SFDC opp was not updated!
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
    get_custom_fields_and_lists
    @owners = User.registered.where(organization_id: current_user.organization_id).ordered_by_first_name
    @project = Project.new
    projects = Project.visible_to(current_user.organization_id, current_user.id)

    # Incrementally apply filters
    params[:close_date] = Project::CLOSE_DATE_RANGE[:ThisQuarter] if params[:close_date].blank?
    projects = projects.close_date_within(params[:close_date]) unless params[:close_date] == 'Any'
    if params[:owner].present? && params[:owner] != "0"
      if params[:owner] == "none"
        projects = projects.where(owner_id: nil)
      else @owners.any? { |o| o.id == params[:owner] }  #check for a valid user_id before using it
        projects = projects.where(owner_id: params[:owner])
      end
    end
    # Stage chart/filter
    stage_chart_result = Project.select("COALESCE(projects.stage, '-Undefined-')").where("projects.id IN (?)", projects.ids).group("COALESCE(projects.stage, '-Undefined-')").sum("projects.amount").sort

    stage_name_picklist = SalesforceOpportunity.get_sfdc_opp_stages(organization: current_user.organization)
    @stage_chart_data = stage_chart_result.sort do |x,y|
      stage_name_x = stage_name_picklist.find{|s| s.first == x.first}
      stage_name_x = stage_name_x.present? ? stage_name_x.second.to_s : '           '+x.first
      stage_name_y = stage_name_picklist.find{|s| s.first == y.first}
      stage_name_y = stage_name_y.present? ? stage_name_y.second.to_s : '           '+y.first
      stage_name_x <=> stage_name_y  # unmatched stage names are sorted to the left of everything
    end.map do |s, a|
      Hashie::Mash.new({ stage_name: s, total_amount: a })
    end
  end

  def index_json
    @MEMBERS_LIST_LIMIT = 8 # Max number of Opportunity members to show in mouse-over tooltip
    # Get an initial list of visible projects
    projects = Project.visible_to(current_user.organization_id, current_user.id)

    total_records = projects.ids.size

    # params[:close_date] = Project::CLOSE_DATE_RANGE[:ThisQuarter] if params[:close_date].blank?
    projects = projects.close_date_within(params[:close_date]) unless params[:close_date] == 'Any'

    if params[:owner].present? && params[:owner] != "0"
      if params[:owner] == "none"
        projects = projects.where(owner_id: nil)
      # else @owners.any? { |o| o.id == params[:owner] }  #check for a valid user_id before using it
      elsif current_user.organization.users.registered.find_by(id: params[:owner])
        projects = projects.where(owner_id: params[:owner])
      end
    end

    projects = projects.where(stage: params[:stage]) if params[:stage].present?

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
      @project_days_inactive = projects.joins(:activities).where.not(activities: { category: [Activity::CATEGORY[:Note], Activity::CATEGORY[:Alert]] }).where('activities.last_sent_date <= ?', Time.current).maximum("activities.last_sent_date") # get last_sent_date
      @project_days_inactive.each { |pid, last_sent_date| @project_days_inactive[pid] = Time.current.to_date.mjd - last_sent_date.in_time_zone.to_date.mjd } # convert last_sent_date to days inactive
      @sparkline = Project.count_activities_by_day_sparkline(projects.ids, current_user.time_zone)
      @days_to_close = Project.days_to_close(projects.ids)
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
        all_members = project.users + project.contacts
        members = all_members.first(@MEMBERS_LIST_LIMIT)
        tooltip = all_members.size == 0 ? '' : " data-toggle=\"tooltip\" data-placement=\"right\" data-html=\"true\" data-original-title=\"<strong>People:</strong><br/> #{ (members.collect {|m| get_full_name(m)}).sort_by{|m| m.upcase}.join('<br/>') } #{ ("<br/><span style='font-style: italic'>and " + (all_members.size - @MEMBERS_LIST_LIMIT).to_s + " more...</span>") if all_members.size > @MEMBERS_LIST_LIMIT } \"".html_safe
        members_html = "<span" + tooltip + "><i class=\"fa fa-users\" style=\"color:#888\"></i> #{all_members.size}</span>"
        [
          ("<input type=\"checkbox\" class=\"bulk-project\" value=\"#{project.id}\">" if current_user.admin?),
          vc.link_to(project.name, project),
          (project.stage.blank?) ? "-" : project.stage,
          (project.amount.nil?) ? "-" : "$"+vc.number_to_human(project.amount),
          (project.forecast.nil?) ? "-" : project.forecast,
          get_full_name(project.project_owner),
          members_html,
          @days_to_close[project.id].nil? ? "-" : @days_to_close[project.id].to_s,
          "<span class='#{@open_risk_count[project.id].present? && @open_risk_count[project.id] > 0 ? 'text-danger' : ''}'>#{@open_risk_count[project.id].to_s}</span>",
          "<div data-sparkline=\"#{@sparkline[project.id].join(', ') if @sparkline[project.id].present?}; column\"></div>",
          @project_days_inactive[project.id].nil? ? "-" : @project_days_inactive[project.id],
          @next_meetings[project.id].nil? ? "-" : @next_meetings[project.id].strftime('%l:%M%p on %B %-d'),
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
    @sfdc_client = SalesforceService.connect_salesforce(user: current_user) if (@project.present? && @project.salesforce_opportunity.present?)
  rescue ActiveRecord::RecordNotFound
    redirect_to root_url, :flash => { :error => "Project not found or is private." }
  end

  def get_account_names
    @account_names = Account.all.select('name', 'id').where("accounts.organization_id = ?", current_user.organization_id).references(:account).order('LOWER(name)')
  end

  # Never trust parameters from the scary internet, only allow the white list through.
  def project_params
    params.require(:project).permit(:name, :description, :is_public, :account_id, :owner_id, :category, :renewal_date, :contract_start_date, :contract_end_date, :contract_arr, :renewal_count, :has_case_study, :is_referenceable, :amount, :stage, :close_date, :expected_revenue, :probability, :forecast)
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
    if params[:owner] 
      cookies[:project_owner] = {value: params[:owner]}
    else
      if cookies[:project_owner]
        params[:owner] = cookies[:project_owner]
      end
    end
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
