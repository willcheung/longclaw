class ProjectsController < ApplicationController
  before_action :set_project, only: [:show, :edit, :update, :destroy]
  before_action :get_account_names, only: [:index, :new, :show, :edit] # So "edit" or "new" modal will display all accounts

  # GET /projects
  # GET /projects.json
  def index
    @title = "Projects"
    # all projects and their accounts, sorted by account name alphabetically
    projects = Project.includes(:account).all.where("accounts.organization_id = ?", current_user.organization_id).references(:account)
    @projects = projects.group_by{|e| e.account}.sort_by{|account| account[0].name}

    # new project
    @project = Project.new
  end

  # GET /projects/1
  # GET /projects/1.json
  def show
    @team = @project.project_members.includes(contact: [:account])
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
        #format.json { head :no_content }
      else
        format.html { render action: 'edit' }
        format.js { render json: @project.errors, status: :unprocessable_entity }
        #format.json { render json: @project.errors, status: :unprocessable_entity }
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
      params.require(:project).permit(:name, :actual_start_date, :project_code, :account_id, :budgeted_hours, :owner_id)
    end
end
