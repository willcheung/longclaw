class AccountsController < ApplicationController
  before_action :set_account, only: [:show, :edit, :update, :destroy, :set_salesforce_account] 
  before_action :get_custom_fields_and_lists, only: [:index, :show]
  before_action :manage_filter_state, only: [:index]

  # GET /accounts
  # GET /accounts.json
  def index
    @CONTACTS_LIST_LIMIT = 8 # Max number of Contacts to show in mouse-over tooltip
    @title = 'Accounts'
    @owners = User.registered.where(organization_id: current_user.organization_id).ordered_by_first_name

    if params[:account_type] == "none"
      @accounts = Account.eager_load(:projects, :user).where("accounts.organization_id = ?", current_user.organization_id).order('accounts.name')
    elsif params[:account_type]
      @accounts = Account.eager_load(:projects, :user).where("accounts.organization_id = ? AND accounts.category = ?", current_user.organization_id, params[:account_type]).order('accounts.name')
    else
      @accounts = Account.eager_load(:projects, :user).where("accounts.organization_id = ?", current_user.organization_id).order('accounts.name')
    end

    # Incrementally apply filters
    if params[:owner].present? && params[:owner] != "0"
      if params[:owner] == "none"
        @accounts = @accounts.where(owner_id: nil)
      else @owners.any? { |o| o.id == params[:owner] }  #check for a valid user_id before using it
          @accounts = @accounts.where(owner_id: params[:owner])
      end
    end
    if params[:account_type].present? && params[:account_type] != "none"
      @accounts = @accounts.where(category: params[:account_type])
    end

    @account_last_activity = Account.eager_load(:activities).where("organization_id = ? AND (projects.is_public=true OR (projects.is_public=false AND projects.owner_id = ?)) AND projects.status = 'Active' AND activities.category not in ('Alert','Note')", current_user.organization_id, current_user.id).order('accounts.name').group("accounts.id").maximum("activities.last_sent_date")
    @account = Account.new
  end

  # GET /accounts/1
  # GET /accounts/1.json
  def show
    @active_projects = @account.projects.visible_to(current_user.organization_id, current_user.id)
    @project_last_email_date = Project.visible_to(current_user.organization_id, current_user.id).includes(:activities).where("activities.category = 'Conversation'").maximum("activities.last_sent_date")
    @project_activities_count_last_7d = Project.visible_to(current_user.organization_id, current_user.id).includes(:activities).where("activities.last_sent_date > (current_date - interval '7 days')").references(:activities).count(:activities)
    @project_pinned = Project.visible_to(current_user.organization_id, current_user.id).includes(:activities).where("activities.is_pinned = true").count(:activities)
    @account_contacts = @account.contacts
    @clearbit_domain = @account.domain? ? @account.domain : (@account_contacts.present? ? @account_contacts.first.email.split("@").last : "")
    @project = Project.new(account: @account)
    @contact = Contact.new(account: @account)

    @opportunity_types = !@custom_lists.blank? ? @custom_lists["Opportunity Type"] : {}  #need this for New Opportunity modal
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
                                                organization_id: current_user.organization_id,
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

  # Handle bulk operations
  def bulk
    render :json => { success: true }.to_json and return if params['account_ids'].blank?
    bulk_accounts = Account.visible_to(current_user).where(id: params['account_ids'])

    case params['operation']
      when 'delete'
        bulk_accounts.destroy_all
      when 'category'
        bulk_accounts.update_all(category: params['value'])
      when 'owner'
        bulk_accounts.update_all(owner_id: params['value'])
      else
        puts 'Invalid bulk operation, no operation performed'
    end

    render :json => {:success => true, :msg => ''}.to_json
  end

  def set_salesforce_account
    @account.update_attributes(salesforce_id: params[:sid])
    respond_to :js
  end

  private

    # Use callbacks to share common setup or constraints between actions.
    def set_account
      begin
        @account = Account.visible_to(current_user).find(params[:id])
      rescue ActiveRecord::RecordNotFound
        redirect_to root_url, :flash => { :error => "Account not found or is private." }
      end
    end

    # Never trust parameters from the scary internet, only allow the white list through.
    def account_params
      params.require(:account).permit(:name, :website, :phone, :description, :address, :category, :revenue_potential)
    end

    def get_custom_fields_and_lists
      @custom_lists = current_user.organization.get_custom_lists_with_options
      @account_types = !@custom_lists.blank? ? @custom_lists["Account Type"] : {}
    end

    def manage_filter_state
      if params[:owner] 
        cookies[:account_owner] = {value: params[:owner]}
      else
        if cookies[:account_owner]
          params[:owner] = cookies[:account_owner]
        end
      end
      if params[:account_type] 
        cookies[:account_type] = {value: params[:account_type]}
      else
        if cookies[:account_type]
          params[:account_type] = cookies[:account_type]
        end
      end
    end

end
