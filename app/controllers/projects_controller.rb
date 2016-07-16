class ProjectsController < ApplicationController
  before_action :set_visible_project, only: [:show, :edit, :render_pinned_tab, :pinned_tab, :tasks_tab, :refresh]
  before_action :set_editable_project, only: [:destroy, :update]
  before_action :get_account_names, only: [:index, :new, :show, :edit] # So "edit" or "new" modal will display all accounts
  before_action :get_show_data, only: [:show, :pinned_tab, :tasks_tab]

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
    unless projects.empty?
      @project_last_activity_date = Project.visible_to(current_user.organization_id, current_user.id).includes(:activities).maximum("activities.last_sent_date")
      @metrics = Project.count_activities_by_day(7, projects.map(&:id))
      @risk_scores = Project.current_risk_score(projects.map(&:id))
    end
    # new project modal
    @project = Project.new

    @owners = User.where(organization_id: current_user.organization_id) 
  end

  # GET /projects/1
  # GET /projects/1.json
  def show
    @category_param = []
    @filter_email = []
    @final_filter_user = []

    # get all possbible email options
    total_activities_email = @project.activities.select('to','from','cc','posted_by','category','is_public').includes(:user).select {|a| a.is_visible_to(current_user) }

    tempSet = Set.new
    total_activities_email.each do |a|
      a.email_addresses.each do |e|
        tempSet.add(e)
      end
      #add notes post_by email
      if !a.user.nil?
        tempSet.add(a.user.email)
      end
    end

    filter_user = User.where('email in (?)',tempSet.to_a)
    filter_contact = Contact.where('email in (?)',tempSet.to_a)
     
    filter_contact.each do |c|
      u = User.new
      u.first_name = c.first_name
      u.last_name = c.last_name
      u.email = c.email
      #avoid contacts with same email
      if tempSet.include?(c.email)
        @final_filter_user.push(u)
        tempSet.delete(c.email)
      end
    end

    filter_user.each do |u|
      @final_filter_user.push(u)
      tempSet.delete(u.email)
    end

    tempSet.each do |s|
      u = User.new
      u.first_name = s
      u.last_name = ''
      u.email = s
      @final_filter_user.push(u)
    end

    @final_filter_user = @final_filter_user.sort_by {|u| u.first_name.downcase}

    activities = []

    # filter by params category
    if(!params[:category].nil? and !params[:category].empty?)
      @category_param = params[:category].split(',')
      temp_activities = @project.activities.where('category in (?)',@category_param).includes(:comments, :user)
    else
      # todo: Right now anyone can mark anything as private ~ should only recipient of activity be able to do it?
      temp_activities = @project.activities.includes(:comments, :user)
    end

    # filter by params email
    if(!params[:emails].nil? and !params[:emails].empty?)
      @filter_email = params[:emails].split(',')

      temp_activities.each do |a|
        @filter_email.each do |e|
          if a.category==Activity::CATEGORY[:Note]
            if a.user.email == e
              activities.push(a)
              break
            end
          else
            if a.email_addresses.include?(e)
              activities.push(a)
              break
            end
          end
        end
      end
    else
      activities = temp_activities
    end

    # filter out not visible items
    @activities_by_month = activities.select {|a| a.is_visible_to(current_user) }.group_by {|a| a.last_sent_date.strftime('%^B %Y') }
    @notifications = @project.notifications.order(:is_complete, :original_due_date)
    @users_reverse = current_user.organization.users.map { |u| [u.id,u.first_name+' '+ u.last_name] }.to_h
  end

  def pinned_tab
    @pinned_activities = @project.activities.pinned.includes(:comments)
    # filter out not visible items
    @pinned_activities = @pinned_activities.select {|a| a.is_visible_to(current_user) }

    render "show"
  end

  def tasks_tab
    visible_activities = Activity.where(project_id: @project.id)
    # select only open tasks where 1. no conversation id 2. conversation is visible 3. conversation has been deleted
    @notifications = @project.notifications.select do |n| 
      n.conversation_id.nil? ||
      visible_activities.any? { |a| n.project_id == a.project_id && n.conversation_id == a.backend_id } ||
      !@project.activities.any? {|a| n.conversation_id == a.backend_id }
    end
    @users_reverse = current_user.organization.users.map { |u| [u.id,u.first_name+' '+ u.last_name] }.to_h

    render "show"
  end

  def refresh
    ContextsmithService.load_emails_from_backend(@project, nil, 300)
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

    render :text =>"" 
  end

  private

  def get_show_data
    # metrics
    @project_last_activity_date = @project.activities.where(category: "Conversation").maximum("activities.last_sent_date")
    project_last_touch = @project.activities.find_by(category: "Conversation", last_sent_date: @project_last_activity_date)
    @project_last_touch_by = project_last_touch ? project_last_touch.from[0].personal : "--"
    visible_activities = @project.activities.select { |a| a.is_visible_to(current_user) }
    # select only open tasks where 1. no conversation id 2. conversation is visible 3. conversation has been deleted
    @project_open_tasks_count = @project.notifications.where(is_complete: false).select do |n| 
      n.conversation_id.nil? ||
      visible_activities.any? { |a| n.project_id == a.project_id && n.conversation_id == a.backend_id } ||
      !@project.activities.any? {|a| n.conversation_id == a.backend_id }
    end.length
    @project_pinned_count = @project.activities.pinned.length
    @project_risk_score = @project.current_risk_score

    # project people
    @project_members = @project.project_members
    @project_subscribers = @project.subscribers

    # for merging projects, for future use
    # @account_projects = @project.account.projects.where.not(id: @project.id).pluck(:id, :name)
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
