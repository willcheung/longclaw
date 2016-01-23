class AccountsController < ApplicationController
  before_action :set_account, only: [:show, :edit, :update, :destroy]

  # GET /accounts
  # GET /accounts.json
  def index
    @title = "Accounts"
    @accounts = Account.eager_load(:projects).all.where("organization_id = ? and (projects.is_public=true OR (projects.is_public=false AND projects.owner_id = ?))", current_user.organization_id, current_user.id).order('accounts.name')
    @account = Account.new
  end

  # GET /accounts/1
  # GET /accounts/1.json
  def show
    @active_projects = @account.projects.visible_to(current_user.id).is_active
    @project_last_email_date = Project.visible_to(current_user.id).includes(:activities).where("activities.category = 'Conversations'").maximum("activities.last_sent_date")
    @project_last_activity_date = Project.visible_to(current_user.id).includes(:activities).maximum("activities.last_sent_date")
    @project_activities_count_last_7d = Project.visible_to(current_user.id).includes(:activities).where("activities.last_sent_date > (current_date - interval '7 days')").references(:activities).count(:activities)
    @project_pinned = Project.visible_to(current_user.id).includes(:activities).where("activities.is_pinned = true").count(:activities)

    @account_contacts = @account.contacts
  end

  # GET /accounts/new
  def new
    @account = Account.new
  end

  # GET /accounts/1/edit
  def edit
  end

  # POST /accounts
  # POST /accounts.json
  def create
    @account = Account.new(account_params.merge(owner_id: current_user.id, 
                                                created_by: current_user.id,
                                                updated_by: current_user.id,
                                                organization_id: current_user.organization.id,
                                                status: 'Active'))

    respond_to do |format|
      if @account.save
        format.html { redirect_to @account, notice: 'Account was successfully created.' }
        #format.json { render action: 'show', status: :created, location: @account }
        format.js { render action: 'show', status: :created, location: @account }
      else
        format.html { render action: 'new' }
        #format.json { render json: @account.errors, status: :unprocessable_entity }
        format.js { render json: @account.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /accounts/1
  # PATCH/PUT /accounts/1.json
  def update
    respond_to do |format|
      if @account.update(account_params.merge(updated_by: current_user.id))
        format.html { redirect_to @account, notice: 'Account was successfully updated.' }
        format.json { head :no_content }
        format.js { render action: 'show', status: :created, location: @account }
      else
        format.html { render action: 'edit' }
        format.json { render json: @account.errors, status: :unprocessable_entity }
        format.js { render json: @account.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /accounts/1
  # DELETE /accounts/1.json
  def destroy
    @account.destroy
    respond_to do |format|
      format.html { redirect_to accounts_url }
      #format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_account
      @account = Account.find(params[:id])
    end

    # Never trust parameters from the scary internet, only allow the white list through.
    def account_params
      params.require(:account).permit(:name, :website, :phone, :description, :address)
    end
end
