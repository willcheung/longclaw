class ProjectsController < ApplicationController
  before_action :check_params_for_valid_dates, only: [:update]
  before_action :set_visible_project, only: [:show, :edit, :tasks_tab, :arg_tab, :lookup, :network_map, :refresh, :filter_timeline, :more_timeline]
  before_action :set_editable_project, only: [:destroy, :update]
  before_action :get_account_names, only: [:index, :new, :show, :edit] # So "edit" or "new" modal will display all accounts
  before_action :get_users_reverse, only: [:index, :show, :filter_timeline, :more_timeline, :tasks_tab, :arg_tab]
  before_action :get_show_data, only: [:show, :tasks_tab, :arg_tab]
  before_action :load_timeline, only: [:show, :filter_timeline, :more_timeline]
  before_action :get_custom_fields_and_lists, only: [:index, :show, :tasks_tab, :arg_tab]
  before_action :project_filter_state, only: [:index]
  

  # GET /projects
  # GET /projects.json
  def index
    @MEMBERS_LIST_LIMIT = 8 # Max number of Opportunity members to show in mouse-over tooltip
    @title = "Opportunities"
    # for filter and bulk owner assignment - use only registered users
    @owners = User.registered.where(organization_id: current_user.organization_id).ordered_by_first_name
    # Get an initial list of visible projects
    projects = Project.visible_to(current_user.organization_id, current_user.id)

    # Incrementally apply filters
    if params[:owner] != "0"
      if params[:owner] == "none"
        projects = projects.where(owner_id: nil)
      else @owners.any? { |o| o.id == params[:owner] }  #check for a valid user_id before using it
          projects = projects.where(owner_id: params[:owner])
      end
    end
    if params[:type] != "none"
      projects = projects.where(category: params[:type])
    end
    
    # all projects and their accounts, sorted by account name alphabetically
    @projects = projects.preload([:users,:contacts,:subscribers,:account]).select("project_subscribers.daily, project_subscribers.weekly").joins("LEFT OUTER JOIN project_subscribers ON project_subscribers.project_id = projects.id AND project_subscribers.user_id = '#{current_user.id}'").group("project_subscribers.id") #.group_by{|e| e.account}.sort_by{|account| account[0].name}

    unless projects.empty?
      @project_days_inactive = projects.joins(:activities).where.not(activities: { category: [Activity::CATEGORY[:Note], Activity::CATEGORY[:Alert]] }).maximum("activities.last_sent_date") # get last_sent_date
      @project_days_inactive.each { |pid, last_sent_date| @project_days_inactive[pid] = Time.current.to_date.mjd - last_sent_date.in_time_zone.to_date.mjd } # convert last_sent_date to days inactive
      @sparkline = Project.count_activities_by_day_sparkline(projects.ids, current_user.time_zone)
      @days_to_close = Project.days_to_close(projects.ids)
      @open_risk_count = Project.open_risk_count(projects.ids)
      #@risk_scores = Project.new_risk_score(projects.ids, current_user.time_zone)
      @next_meetings = Activity.meetings.next_week.select("project_id, min(last_sent_date) as next_meeting").where(project_id: projects.ids).group("project_id")
      @next_meetings = Hash[@next_meetings.map { |p| [p.project_id, p.next_meeting] }]
    end

    # new project modal
    @project = Project.new 
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
    @data = @project.activities.where(category: %w(Conversation Meeting))

    render "show"
  end

  def network_map
    respond_to do |format|
      format.json { render json: @project.network_map}
    end
  end

  def lookup
    pinned = @project.conversations.pinned
    meetings = @project.meetings
    members = (@project.users + @project.contacts).map do |m|
      pin = pinned.select { |p| p.from.first.address == m.email || p.posted_by == m.id }
      meet = meetings.select { |p| p.from.first.address == m.email || p.posted_by == m.id }
      {
        name: get_full_name(m),
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
    # Subscribe current_user as weekly / daily follower because s/he created the project
    @project.subscribers.new(user: current_user)

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

  def get_users_reverse
    @users_reverse = get_current_org_users
  end

  def get_show_data
    @project_close_date = @project.close_date.nil? ? nil : @project.close_date.strftime('%Y-%m-%d')
    @project_renewal_date = @project.renewal_date.nil? ? nil : @project.renewal_date.strftime('%Y-%m-%d')

    # metrics
    #@project_risk_score = @project.new_risk_score(current_user.time_zone)
    @project_open_risks_count = @project.notifications.open.alerts.count
    @project_pinned_count = @project.activities.pinned.visible_to(current_user.email).count
    @project_open_tasks_count = @project.notifications.open.count

    # Removing RAG status - old metric
    # project_rag_score = @project.activities.latest_rag_score.first

    # if project_rag_score
    #   @project_rag_status = project_rag_score['rag_score']
    # end

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
    activities = @project.activities.visible_to(current_user.email).includes(:notifications, :attachments, :comments)
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

  def set_editable_project
    @project = Project.joins(:account)
                      .where('accounts.organization_id = ?
                              AND (projects.is_public=true
                                    OR (projects.is_public=false AND projects.owner_id = ?))', current_user.organization_id, current_user.id)
                      .find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to root_url, :flash => { :error => "Project not found or is private." }
  end

  def get_account_names
    @account_names = Account.all.select('name', 'id').where("accounts.organization_id = ?", current_user.organization_id).references(:account).order('LOWER(name)')
  end

  # Never trust parameters from the scary internet, only allow the white list through.
  def project_params
    params.require(:project).permit(:name, :description, :is_public, :account_id, :owner_id, :category, :renewal_date, :contract_start_date, :contract_end_date, :contract_arr, :renewal_count, :has_case_study, :is_referenceable, :amount, :stage, :close_date, :expected_revenue)
  end

  # A list of the param names that can be used for filtering the Project list
  def filtering_params(params)
    params.slice(:status, :location, :starts_with)
  end

  def get_custom_fields_and_lists
    custom_lists = current_user.organization.get_custom_lists_with_options
    @opportunity_types = !custom_lists.blank? ? custom_lists["Opportunity Type"] : {}
    @custom_lists = current_user.organization.get_custom_lists_with_options
    @opportunity_types = !@custom_lists.blank? ? @custom_lists["Opportunity Type"] : {}
  end

  def project_filter_state
    if params[:owner] 
      cookies[:owner] = {value: params[:owner]}
    else
      if cookies[:owner]
        params[:owner] = cookies[:owner]
      end
    end
    if params[:type] 
      cookies[:type] = {value: params[:type]}
    else
      if cookies[:type]
        params[:type] = cookies[:type]
      end
    end
  end

  # Allows smooth update of close_date and renewal_date using jQuery Datepicker widget.  In particular because of an different/incompatible Date format sent by widget to this controller to update a field of a non-timestamp (simple Date) type.
  def check_params_for_valid_dates
    params["project"][:close_date] = parse_valid_date(params["project"][:close_date]) if params["project"][:close_date].present?
    params["project"][:renewal_date] = parse_valid_date(params["project"][:renewal_date]) if params["project"][:renewal_date].present?
  end

  # Attempt to parse a Date from datestr using recognized formats %Y-%m-%d or %m/%d/%Y, then return the parsed Date. Otherwise, return nil.
  def parse_valid_date(datestr)
    return nil if datestr.nil?

    parsed_date = nil
    begin
      parsed_date = Date.strptime(datestr, '%Y-%m-%d')
    rescue ArgumentError => e
      parsed_date = Date.strptime(datestr, '%m/%d/%Y')
    rescue => e
      # Do nothing
    end
    parsed_date
  end
end
