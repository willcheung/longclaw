class ProjectsController < ApplicationController
  before_action :set_visible_project, only: [:show, :edit, :render_pinned_tab, :pinned_tab, :tasks_tab, :insights_tab, :arg_tab, :lookup, :network_map, :refresh, :filter_timeline, :more_timeline]
  before_action :set_editable_project, only: [:destroy, :update]
  before_action :get_account_names, only: [:index, :new, :show, :edit] # So "edit" or "new" modal will display all accounts
  before_action :get_users_reverse, only: [:index, :show, :filter_timeline, :more_timeline, :pinned_tab, :tasks_tab, :insights_tab, :arg_tab]
  before_action :get_show_data, only: [:show, :pinned_tab, :tasks_tab, :insights_tab, :arg_tab]
  before_action :load_timeline, only: [:show, :filter_timeline, :more_timeline]

  # GET /projects
  # GET /projects.json
  def index
    @title = "Streams"

    # for filter and bulk owner assignment
    @owners = User.where(organization_id: current_user.organization_id)

    # Get an initial list of visible projects
    projects = Project.visible_to(current_user.organization_id, current_user.id)
    
    # Incrementally apply filters
    if !params[:owner].nil?
      if params["owner"]=="none"
        projects = projects.where(owner_id: nil)
      elsif @owners.any? { |o| o.id == params[:owner] }  #check for a valid user_id before using it
        projects = projects.where(owner_id: params[:owner]);
      end
    end 
    if params[:type]
      projects = projects.where(category: params[:type])
    end

    # all projects and their accounts, sorted by account name alphabetically
    @projects = projects.preload([:users,:contacts,:subscribers,:account]).select("COUNT(DISTINCT activities.id) AS activity_count, project_subscribers.daily, project_subscribers.weekly").joins(:activities, "LEFT JOIN project_subscribers ON project_subscribers.project_id = projects.id AND project_subscribers.user_id = '#{current_user.id}'").group("project_subscribers.id") #.group_by{|e| e.account}.sort_by{|account| account[0].name}
    
    unless projects.empty?  #@projects.empty  should be that?
      @project_days_inactive = projects.joins(:activities).where.not(activities: { category: Activity::CATEGORY[:Note] }).maximum("activities.last_sent_date") # get last_sent_date
      @project_days_inactive.each { |pid, last_sent_date| @project_days_inactive[pid] = Time.current.to_date.mjd - last_sent_date.in_time_zone.to_date.mjd } # convert last_sent_date to days inactive
      @metrics = Project.count_activities_by_day(7, projects.map(&:id))
      @risk_scores = Project.new_risk_score(projects.pluck(:id), current_user.time_zone)
      @open_risk_count = Project.open_risk_count(projects.map(&:id))
      @rag_status = Project.current_rag_score(projects.map(&:id))
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
  end

  def filter_timeline
    respond_to :js
  end

  def more_timeline
    respond_to :js
  end

  def pinned_tab
    @pinned_activities = @project.activities.pinned.visible_to(current_user.email).includes(:comments)

    render "show"
  end

  def tasks_tab
    # show every risk regardless of private conversation
    @notifications = @project.notifications

    render "show"
  end

  def insights_tab
    @risk_score_trend = @project.new_risk_score_trend(current_user.time_zone)

    # Engagement Volume Chart
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
    # big refresh when no activities (normally a new stream), small refresh otherwise
    if @project.activities.count == 0
      puts "<><><> Big asynchronous refresh incoming... <><><>"
      ContextsmithService.load_emails_from_backend(@project, 2000)
      ContextsmithService.load_calendar_from_backend(@project, 1000)
      # 6.months.ago or more is too long ago, returns nil. 150.days is just less than 6.months and should work
    else
      ContextsmithService.load_emails_from_backend(@project)
      ContextsmithService.load_calendar_from_backend(@project, 100, 1.day.ago.to_i)
    end
    redirect_to :back
  end

  def render_pinned_tab
    @pinned_activities = @project.activities.pinned.includes(:comments)
    respond_to :js
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
    @project.project_members.new(user: current_user)
    @project.subscribers.new(user: current_user)

      respond_to do |format|
        if params[:commit] == 'Create Stream' 
          members = @project.account.contacts
            members.each do |input|
              new_member = @project.project_members.new(contact: input)
            end
          if @project.save
            #Big First Refresh, potentially won't need big refresh in the refresh method above
            ContextsmithService.load_emails_from_backend(@project, nil, 2000)
            ContextsmithService.load_calendar_from_backend(@project, Time.current.to_i, 150.days.ago.to_i, 1000)
            format.html { redirect_to @project, notice: 'Project was successfully created.' }
            format.js
            #format.json { render action: 'show', status: :created, location: @project }
          else
            format.html { render action: 'new' }
            format.js { render json: @project.errors, status: :unprocessable_entity }
            #format.json { render json: @project.errors, status: :unprocessable_entity }
          end
        else params[:commit] == 'Custom Stream'
          if @project.save
            format.html { redirect_to @project, notice: 'Project was successfully created.' }
            format.js
            #format.json { render action: 'show', status: :created, location: @project 
          else
            puts "Fail project saved"
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

  def bulk
    newArray = params["selected"].map { |key, value| key }

    if(params["operation"]=="delete")
      bulk_delete(newArray)
    elsif params["operation"]=="category"
      bulk_update_category(newArray, params["value"])
    elsif params["operation"]=="owner"
      bulk_update_owner(newArray, params["value"])
    end

    render :json => {:success => true, :msg => ''}.to_json
  end

  private

  def get_users_reverse
    @users_reverse = get_current_org_users
  end

  def get_show_data
    # metrics
    @project_risk_score = @project.new_risk_score(current_user.time_zone)
    @project_open_risks_count = @project.notifications.open.risks.count
    @project_pinned_count = @project.activities.pinned.count
    @project_open_tasks_count = @project.notifications.open.count
    project_rag_score = @project.activities.latest_rag_score.first

    if project_rag_score
      @project_rag_status = project_rag_score['rag_score']
    end

    # old metrics
    # @project_last_activity_date = @project.activities.where.not(category: Activity::CATEGORY[:Note]).maximum("activities.last_sent_date")
    # project_last_touch = @project.conversations.find_by(last_sent_date: @project_last_activity_date)
    # @project_last_touch_by = project_last_touch ? project_last_touch.from[0].personal : "--"

    # project people
    @project_members = @project.project_members
    project_subscribers = @project.subscribers
    @daily_subscribers = project_subscribers.daily
    @weekly_subscribers = project_subscribers.weekly
    @suggested_members = @project.project_members_all.pending
    @user_subscription = project_subscribers.where(user: current_user).take

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
  end

  def bulk_update_owner(array_of_id, new_owner)
    if(!array_of_id.nil?)
      Project.where("id IN ( '#{array_of_id.join("','")}' )").update_all(owner_id: new_owner)
    end
  end

  def bulk_update_category(array_of_id, new_type)
    if(!array_of_id.nil?)
      Project.where("id IN ( '#{array_of_id.join("','")}' )").update_all(category: new_type)
    end
  end

  def bulk_delete(array_of_id)
    if(!array_of_id.nil?)
      Project.where("id IN ( '#{array_of_id.join("','")}' )").destroy_all
    end
  end

  # Use callbacks to share common setup or constraints between actions.
  def set_visible_project
    begin
      @project = Project.visible_to(current_user.organization_id, current_user.id).find(params[:id])
    rescue ActiveRecord::RecordNotFound
      redirect_to root_url, :flash => { :error => "Project not found or is private." }
    end
  end

  def set_editable_project
    @project = Project.joins(:account)
                      .where('accounts.organization_id = ?
                              AND (projects.is_public=true
                                    OR (projects.is_public=false AND projects.owner_id = ?))', current_user.organization_id, current_user.id)
                      .find(params[:id])
  end

  def get_account_names
    @account_names = Account.all.select('name', 'id').where("accounts.organization_id = ?", current_user.organization_id).references(:account).order('LOWER(name)')
  end

  # Never trust parameters from the scary internet, only allow the white list through.
  def project_params
    params.require(:project).permit(:name, :description, :is_public, :project_code, :account_id, :budgeted_hours, :owner_id, :category)
  end

  # A list of the param names that can be used for filtering the Project list
  def filtering_params(params)
    params.slice(:status, :location, :starts_with)
  end

end
