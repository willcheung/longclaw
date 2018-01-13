class AccountsController < ApplicationController
  before_action :set_account, only: [:show, :edit, :update, :destroy, :set_salesforce_account] 
  before_action :get_custom_fields_and_lists, only: [:show]
  before_action :manage_filter_state, only: [:index]

  # GET /accounts
  # GET /accounts.json
  def index
    respond_to do |format|
      format.html { index_html }
      format.json { render json: index_json }
    end
  end

  # GET /accounts/1
  # GET /accounts/1.json
  def show
    @active_projects = @account.projects.visible_to(current_user.organization_id, current_user.id)
    @projects = @active_projects.select("projects.close_date AS close_date, projects.stage, projects.amount, projects.close_date - current_date AS days_to_close").map{|p| [p.id,p]}.to_h
    @project_last_email_date = @active_projects.includes(:activities).where("activities.category = ?", Activity::CATEGORY[:Conversation]).maximum("activities.last_sent_date")
    # @project_activities_count_last_7d = Project.visible_to(current_user.organization_id, current_user.id).includes(:activities).where("activities.last_sent_date > (current_date - interval '7 days')").references(:activities).count(:activities)
    # @project_pinned = Project.visible_to(current_user.organization_id, current_user.id).includes(:activities).where("activities.is_pinned = true").count(:activities)
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

        if @sfdc_client
          update_result = SalesforceAccount.update_all_salesforce(client: @sfdc_client, salesforce_account: @account.salesforce_accounts.first, fields: account_params, current_user: current_user) 
          puts "*** SFDC error: Error in AccountsController.update during update of linked SFDC account. Detail: #{update_result[:detail]} ***" if update_result[:status] == "ERROR" # TODO: Warn the user SFDC acct was not updated!
        end
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

  def index_html
    # puts "\n\n\t************ index_html *************\n"
    # puts "\tparams[:account_type]: #{params[:account_type]}"
    # puts "\tparams[:owner]: #{params[:owner]}"
    # puts "\n\n" 

    get_custom_fields_and_lists
    @owners = User.registered.where(organization_id: current_user.organization_id).ordered_by_first_name
    @account = Account.new
  end

  def index_json
    # puts "\n\n\t************ index_json *************\n"
    # puts "\tparams[:account_type]: #{params[:account_type]}"
    # puts "\tparams[:owner]: #{params[:owner]}"
    # puts "\n\n" 

    @CONTACTS_LIST_LIMIT = 8 # Max number of Contacts to show in mouse-over tooltip
    @owners = User.registered.where(organization_id: current_user.organization_id).ordered_by_first_name
    @accounts = Account.includes(:projects, :user, :contacts).where(organization_id: current_user.organization_id)
    total_records = @accounts.count

    # Incrementally apply filters
    if params[:owner].present?
      if (!params[:owner].include? "None")
        @accounts = @accounts.where(owner_id: params[:owner])  if @owners.any? { |o| params[:owner].include? o.id }  #check for a valid user_id before using it
      else
        @accounts = @accounts.where("\"accounts\".owner_id IS NULL OR \"accounts\".owner_id IN (?)", params[:owner].select{|o| o != "None"})
      end
    end

    @accounts = @accounts.where(category: params[:account_type]) if params[:account_type].present?

    # searching
    @accounts = @accounts.where('LOWER(name) LIKE LOWER(:search) OR LOWER(category) LIKE LOWER(:search) OR LOWER(website) LIKE LOWER(:search)', search: "%#{params[:sSearch]}%") if params[:sSearch].present?

    # ordering
    columns = [nil, 'name', 'category', nil, nil, nil, nil, 'website']
    sort_by = columns[params[:iSortCol_0].to_i]
    @accounts = @accounts.order("LOWER(#{sort_by}) #{params[:sSortDir_0]} NULLS LAST")


    # PAGINATE HERE
    total_display_records = @accounts.count
    per_page = params[:iDisplayLength].to_i > 0 ? params[:iDisplayLength].to_i : 10
    page = params[:iDisplayStart].to_i/per_page
    @accounts = @accounts.limit(per_page).offset(per_page * page)

    @account_last_activity = Account.eager_load(:activities).where("organization_id = ? AND (projects.is_public=true OR (projects.is_public=false AND projects.owner_id = ?)) AND projects.status = 'Active' AND activities.category not in ('Alert','Note') AND activities.last_sent_date <= ?", current_user.organization_id, current_user.id, Time.current).order('accounts.name').group("accounts.id").maximum("activities.last_sent_date")

    vc = view_context

    {
      sEcho: params[:sEcho].to_i,
      iTotalRecords: total_records,
      iTotalDisplayRecords: total_display_records,
      aaData: @accounts.map do |account|
        contacts = account.contacts.first(@CONTACTS_LIST_LIMIT)
        tooltip = account.contacts.size == 0 ? '' : " data-toggle=\"tooltip\" data-placement=\"right\" data-html=\"true\" data-original-title=\"<strong>Contacts:</strong><br/> #{ (contacts.collect{|c| get_full_name(c)}).sort_by{|c| c.upcase}.join('<br/>') } #{ ("<br/><span style='font-style: italic'>and " + (account.contacts.size - @CONTACTS_LIST_LIMIT).to_s + " more...</span>") if account.contacts.size > @CONTACTS_LIST_LIMIT } \"".html_safe
        contacts_html = "<span" + tooltip + "><i class=\"fa fa-users\" style=\"color:#888\"></i> #{account.contacts.size}</span>"
        [
          ("<input type=\"checkbox\" class=\"bulk-account\" value=\"#{account.id}\">" if current_user.admin?),
          vc.link_to(account.name, account),
          account.category,
          get_full_name(account.user),
          contacts_html,
          account.projects.visible_to(current_user.organization_id, current_user.id).ids.size,
          @account_last_activity[account.id].nil? ? '' : ((Time.current - @account_last_activity[account.id])/86400).to_i,
          account.website
        ]
      end
    }
  end

    # Use callbacks to share common setup or constraints between actions.
    def set_account
      begin
        @account = Account.visible_to(current_user).find(params[:id])
        if (@account.present? && @account.salesforce_accounts.first.present?)
          sfdc_oauthuser = SalesforceController.get_sfdc_oauthuser(user: current_user) || SalesforceController.get_sfdc_oauthuser(organization: current_user.organization)  # Use current user's SFDC login/connection if available; otherwise, use admin's SFDC login/connection regardless of current user's role
          
          @sfdc_client = SalesforceService.connect_salesforce(sfdc_oauthuser: sfdc_oauthuser) if sfdc_oauthuser.present?

          puts "****SFDC**** Warning: no SFDC connection is available or can be established for user=#{current_user.email}, organization=#{current_user.organization.name}. Linked Salesforce account was not be updated!" if @sfdc_client.nil? # TODO: Issue a warning to the user that the linked SFDC acct was not updated! 
        end
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
        params[:owner] = cookies[:account_owner].present? ? cookies[:account_owner].split("&") : []
      end
      if params[:account_type] 
        cookies[:account_type] = {value: params[:account_type]}
      else
        params[:account_type] = cookies[:account_type].present? ? cookies[:account_type].split("&") : []
      end
    end
end
