class ProjectsController < ApplicationController
  before_action :set_project, only: [:show, :edit, :update, :destroy]
  before_action :get_account_names, only: [:index, :new, :show, :edit] # So "edit" or "new" modal will display all accounts

  # GET /projects
  # GET /projects.json
  def index
    @title = "Projects"
    projects = []

    # all projects and their accounts, sorted by account name alphabetically
    projects = Project.is_public(current_user.id).includes(:account).all.where("accounts.organization_id = ? AND is_confirmed = true", current_user.organization_id).references(:account)
    @projects = projects.group_by{|e| e.account}.sort_by{|account| account[0].name}

    # new project modal
    @project = Project.new
  end

  # GET /projects/1
  # GET /projects/1.json
  def show
    @team = @project.contacts.includes(:account) + @project.users

    max=50
    base_url = ENV["csback_base_url"] + "/newsfeed/search"

    if ENV["RAILS_ENV"] == 'production'
      current_user.refresh_token! if current_user.token_expired?
      token = current_user.oauth_access_token
      email = current_user.email
    else
      # DEBUG
      u = User.find_by_email('indifferenzetester@gmail.com')
      u.refresh_token! if u.token_expired?
      token = u.oauth_access_token
      email = u.email
    end

    ex_clusters = [@project.contacts.map(&:email)]
    
    final_url = base_url + "?token=" + token + "&email=" + email + "&max=" + max.to_s + "&ex_clusters=" + ex_clusters.to_s + "&in_domain=comprehend.com"
    logger.info "Calling remote service: " + final_url

    url = URI.parse(final_url)
    req = Net::HTTP::Get.new(url.to_s)
    res = Net::HTTP.start(url.host, url.port) { |http| http.request(req) }
    data = JSON.parse(res.body.to_s)

    Activity.load(data, @project, current_user.id)
    @activities = @project.activities.includes(:comments)
    @pinned_activities = @project.activities.pinned.includes(:comments)
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
    @project = Project.new(project_params)
    @project = Project.new(project_params.merge(status: 'Active', 
                                                owner_id: current_user.id,
                                                is_confirmed: true,
                                                created_by: current_user.id,
                                                updated_by: current_user.id))

    respond_to do |format|
      if @project.save
        format.html { redirect_to @project, notice: 'Project was successfully created.' }
        format.js { render action: 'show', status: :created, location: @project }
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
        format.js { render action: 'show', status: :created, location: @project }
        format.json { head :no_content }
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
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_project
    @project = Project.find(params[:id])
  end

  def get_account_names
    @account_names = Account.all.select('name', 'id').where("accounts.organization_id = ?", current_user.organization_id).references(:account).order('LOWER(name)')
  end

  # Never trust parameters from the scary internet, only allow the white list through.
  def project_params
    params.require(:project).permit(:name, :is_public, :project_code, :account_id, :budgeted_hours, :owner_id)
  end

  # A list of the param names that can be used for filtering the Project list
  def filtering_params(params)
    params.slice(:status, :location, :starts_with)
  end
end
