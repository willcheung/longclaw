class ProjectsController < ApplicationController
  before_action :set_visible_project, only: [:show, :edit, :render_pinned_tab, :pinned_tab, :tasks_tab, :insights_tab, :lookup, :network_map, :refresh, :show_timeline, :more_timeline]
  before_action :set_editable_project, only: [:destroy, :update]
  before_action :get_account_names, only: [:index, :new, :show, :edit] # So "edit" or "new" modal will display all accounts
  before_action :get_show_data, only: [:show, :pinned_tab, :tasks_tab, :insights_tab]
  before_action :load_timeline, only: [:show, :filter_timeline, :more_timeline]

  # GET /projects
  # GET /projects.json
  def index
    @title = "Projects"

    # all projects and their accounts, sorted by account name alphabetically
    if params[:type]
      projects = Project.visible_to(current_user.organization_id, current_user.id).where(category: params[:type]).preload([:users,:contacts,:subscribers,:account]).select("COUNT(DISTINCT activities.id) AS activity_count").joins("LEFT JOIN activities ON activities.project_id = projects.id").group("projects.id")
    else
      projects = Project.visible_to(current_user.organization_id, current_user.id).preload([:users,:contacts,:subscribers,:account]).select("COUNT(DISTINCT activities.id) AS activity_count").joins("LEFT JOIN activities ON activities.project_id = projects.id").group("projects.id")
    end

    @projects = projects.group_by{|e| e.account}.sort_by{|account| account[0].name}
    unless projects.empty?
      @project_last_activity_date = Project.visible_to(current_user.organization_id, current_user.id).includes(:activities).maximum("activities.last_sent_date")
      @metrics = Project.count_activities_by_day(7, projects.map(&:id))
      @risk_scores = Project.current_risk_score(projects.map(&:id), current_user.time_zone)
      @open_risk_count = Project.open_risk_count(projects.map(&:id))
    end
    # new project modal
    @project = Project.new

    # for bulk owner assignment
    @owners = User.where(organization_id: current_user.organization_id)
    # for single best_in_place owner assignment
    @users_reverse = current_user.organization.users.order(:first_name).map { |u| [u.id,u.first_name+' '+ u.last_name] }.to_h 
  end

  # GET /projects/1
  # GET /projects/1.json
  def show
    # get data to populate filters
    @final_filter_user = Activity.all_involved_user(@project, current_user)
    activities_by_date = @project.activities.visible_to(current_user.email).pluck(:last_sent_date).group_by { |a| Time.zone.at(a).to_date }
    @activities_by_date = activities_by_date.map do |date, activities|
      Hashie::Mash.new(date: date.to_time.to_i*1000, num_activities: activities.length)
    end
    @activities_by_date = @activities_by_date.sort {|x, y| x.date <=> y.date }
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
    ContextsmithService.load_emails_from_backend(@project, nil, 300)
    ContextsmithService.load_calendar_from_backend(@project, Time.current.to_i, 1.year.ago.to_i, 300)
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
      if @project.save
        format.html { redirect_to @project, notice: 'Project was successfully created.' }
        format.js 
        #format.json { render action: 'show', status: :created, location: @project }
      else
        format.html { render action: 'new' }
        format.js { render json: @project.errors, status: :unprocessable_entity }
        #format.json { render json: @project.errors, status: :unprocessable_entity }
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

  def get_show_data
    # metrics
    @project_risk_score = @project.current_risk_score(current_user.time_zone)
    @project_open_risks_count = @project.notifications.open.risks.count
    @project_last_activity_date = @project.conversations.maximum("activities.last_sent_date")
    @project_pinned_count = @project.activities.pinned.count
    @project_open_tasks_count = @project.notifications.open.count

    # old metrics
    # project_last_touch = @project.conversations.find_by(last_sent_date: @project_last_activity_date)
    # @project_last_touch_by = project_last_touch ? project_last_touch.from[0].personal : "--"

    # project people
    @project_members = @project.project_members
    @project_subscribers = @project.subscribers
    @suggested_members = @project.project_members_all.pending

    # array of users for best_in_place assignment
    @users_reverse = current_user.organization.users.order(:first_name).map { |u| [u.id,u.first_name+' '+ u.last_name] }.to_h

    # for merging projects, for future use
    # @account_projects = @project.account.projects.where.not(id: @project.id).pluck(:id, :name)
  end

  def load_timeline
    activities = @project.activities.visible_to(current_user.email)
    # filter by categories
    @filter_category = []
    unless params[:category].blank?
      @filter_category = params[:category].split(',')
      activities = activities.where(category: @filter_category)
    end
    # filter by people
    @filter_email = []
    unless params[:emails].blank?
      @filter_email = params[:email].split(',')
      users = User.where(email: @filter_email).pluck(:id)
      where_email_clause = @filter_email.map { |e| '"from" || "to" || "cc" @> \'[{"address":"#{e}"}]\'::jsonb' }.join(' OR ') + " OR posted_by IN ('#{users.join("','")}')"
      activities = activities.where(where_email_clause)
    end
    # filter by time
    ### TODO: add time filter logic here
    # pagination
    page_size = 10
    @page = params[:page].blank? ? 1 : params[:page].to_i
    @last_page = (activities.count - (page_size * @page)) > 0 # check whether there is another page to load
    activities = activities.limit(page_size).offset(page_size * (@page - 1)).includes(:notifications, :comments)
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
