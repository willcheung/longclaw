class ProjectsController < ApplicationController
  before_action :set_visible_project, only: [:show, :edit, :render_pinned_tab]
  before_action :set_editable_project, only: [:destroy, :update]
  before_action :get_account_names, only: [:index, :new, :show, :edit] # So "edit" or "new" modal will display all accounts

  # GET /projects
  # GET /projects.json
  def index
    @title = "Projects"

    # all projects and their accounts, sorted by account name alphabetically
    if params[:type]
      projects = Project.visible_to(current_user.organization_id, current_user.id).group("accounts.id").where(category: params[:type]).preload([:users,:contacts,:subscribers, :account, :activities])
    else
      projects = Project.visible_to(current_user.organization_id, current_user.id).group("accounts.id").preload([:users,:contacts,:subscribers, :account, :activities])
    end

    @projects = projects.group_by{|e| e.account}.sort_by{|account| account[0].name}
    @project_last_activity_date = Project.visible_to(current_user.organization_id, current_user.id).includes(:activities).maximum("activities.last_sent_date")
    @metrics = Project.count_activities_by_day(7, projects.map(&:id)) if !projects.empty?
    # new project modal
    @project = Project.new
  end

  # GET /projects/1
  # GET /projects/1.json
  def show
    # metrics
    @project_last_activity_date = @project.activities.where(category: "Conversation").maximum("activities.last_sent_date")
    @project_last_touch_by = @project.activities.find_by(category: "Conversation", last_sent_date: @project_last_activity_date).from[0].personal
    @project_open_tasks = @project.notifications.where(is_complete: false).length
    # Inaccurate count of activities, counts number of active conversations, but will not count if multiple emails occurred in same conversation
    # @project_activities_count_last_7d = @project.activities.where("activities.last_sent_date > (current_date - interval '7 days')").count(:activities)

    @activities = @project.activities.includes(:comments)
    @pinned_activities = @project.activities.pinned.includes(:comments)
    @project_members = @project.project_members
    @project_subscribers = @project.subscribers

    # filter out not visible items
    @activities = @activities.select {|a| a.is_visible_to(current_user) }
    @pinned_activities = @pinned_activities.select {|a| a.is_visible_to(current_user) }

    # todo: Right now anyone can mark anything as private ~ should only recipient of activity be able to do it?

    @account_projects = @project.account.projects.where.not(id: @project.id).pluck(:id, :name)
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
                                                updated_by: current_user.id))

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

  private

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
