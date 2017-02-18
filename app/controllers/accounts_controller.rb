class AccountsController < ApplicationController
  before_action :set_account, only: [:show, :edit, :update, :destroy, :set_salesforce_account] 
  before_action :get_custom_fields_and_lists, only: [:index, :show]

  # GET /accounts
  # GET /accounts.json
  def index
    @title = 'Accounts'

    if params[:type]
      @accounts = Account.eager_load(:projects, :user).where('accounts.category = ? and accounts.organization_id = ? and (projects.id IS NULL OR projects.is_public=true OR (projects.is_public=false AND projects.owner_id = ?))', params[:type], current_user.organization_id, current_user.id).order('accounts.name')
    else
      @accounts = Account.eager_load(:projects, :user).where('accounts.organization_id = ? and (projects.id IS NULL OR projects.is_public=true OR (projects.is_public=false AND projects.owner_id = ?))', current_user.organization_id, current_user.id).order('accounts.name')
    end
    
    @account_last_activity = Account.eager_load(:activities).where("organization_id = ? and (projects.is_public=true OR (projects.is_public=false AND projects.owner_id = ?))", current_user.organization_id, current_user.id).order('accounts.name').group("accounts.id").maximum("activities.last_sent_date")
    @account = Account.new

    @owners = User.where(organization_id: current_user.organization_id)
  end

  # GET /accounts/1
  # GET /accounts/1.json
  def show
    @active_projects = @account.projects.visible_to(current_user.organization_id, current_user.id).is_active
    @project_last_email_date = Project.visible_to(current_user.organization_id, current_user.id).includes(:activities).where("activities.category = 'Conversation'").maximum("activities.last_sent_date")
    @project_activities_count_last_7d = Project.visible_to(current_user.organization_id, current_user.id).includes(:activities).where("activities.last_sent_date > (current_date - interval '7 days')").references(:activities).count(:activities)
    @project_pinned = Project.visible_to(current_user.organization_id, current_user.id).includes(:activities).where("activities.is_pinned = true").count(:activities)

    @account_contacts = @account.contacts
    @project = Project.new(account: @account)

    @stream_types = !@custom_lists.blank? ? @custom_lists["Stream Type"] : {}  #need this for New Stream modal
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
        format.json { respond_with_bip(@account) }
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


  def set_salesforce_account
    @account.update_attributes(salesforce_id: params[:sid])
    respond_to :js

  end

  private
    def bulk_update_owner(array_of_id, new_owner)
      if(!array_of_id.nil?)
        Account.where("id IN ( '#{array_of_id.join("','")}' )").update_all(owner_id: new_owner)
      end
    end

    def bulk_update_category(array_of_id, new_type)
      if(!array_of_id.nil?)
        Account.where("id IN ( '#{array_of_id.join("','")}' )").update_all(category: new_type)
      end
    end

    def bulk_delete(array_of_id)
      if(!array_of_id.nil?)
        Account.where("id IN ( '#{array_of_id.join("','")}' )").destroy_all
      end
    end

    # Use callbacks to share common setup or constraints between actions.
    def set_account
      @account = Account.find(params[:id])
    end

    # Never trust parameters from the scary internet, only allow the white list through.
    def account_params
      params.require(:account).permit(:name, :website, :phone, :description, :address, :category, :revenue_potential)
    end

    def get_custom_fields_and_lists
      @custom_lists = current_user.organization.get_custom_lists_with_options
      @account_types = !@custom_lists.blank? ? @custom_lists["Account Type"] : {}
    end
end
