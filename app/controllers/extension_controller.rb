class ExtensionController < ApplicationController
  layout "extension", except: [:test, :new]

  before_action :set_account_and_project, only: [:account, :alerts_tasks, :contacts, :metrics]
  before_action :get_account_types, only: [:no_account]
  before_action :set_salesforce_user

  def test
    render layout: "empty"
  end

  def index
  end

  def new
    # render a copy of the devise/sessions.new page that opens Google Account Chooser as a popup
    # store "/extension" as return location for when OmniauthCallbacksController#google_oauth2 calls sign_in_and_redirect
    store_location_for(:user, extension_path(login: true))
    render layout: "empty"
  end

  def no_account
    @domain = URI.unescape(params[:domain], '%2E')
    @account = Account.new
  end

  def private_domain
  end

  def account
    @activities = @project.activities.visible_to(current_user.email).take(8)
  end

  def alerts_tasks
    @notifications = @project.notifications.order(:is_complete).take(15)
    @users_reverse = get_current_org_users
  end

  def contacts
    @project_members = @project.project_members
    @suggested_members = @project.project_members_all.pending
  end

  def metrics
  end

  def create_account
    @account = Account.new(account_params.merge(
      owner_id: current_user.id, 
      created_by: current_user.id,
      updated_by: current_user.id,
      organization_id: current_user.organization_id,
      status: 'Active')
    )

    respond_to do |format|
      if @account.save
        if create_project
          @project.subscribers.create(user: current_user)
          format.html { redirect_to extension_account_path(internal: params[:internal], external: params[:external]), notice: 'Account Stream was successfully created.' }
          format.js
        else
          format.html { render action: 'no_account' }
          format.js { render json: @project.errors, status: :unprocessable_entity }
        end
      else
        format.html { render action: 'no_account' }
        format.js { render json: @account.errors, status: :unprocessable_entity }
      end
    end
  end

  private

  def set_account_and_project
    # p "*** set account and project ***"
    # p params
    ### url example: .../extension/account?internal%5B0%5D%5B%5D=Will%20Cheung&internal%5B0%5D%5B%5D=wcheung%40contextsmith.com&internal%5B1%5D%5B%5D=Kelvin%20Lu&internal%5B1%5D%5B%5D=klu%40contextsmith.com&internal%5B2%5D%5B%5D=Richard%20Wang&internal%5B2%5D%5B%5D=rcwang%40contextsmith.com&internal%5B3%5D%5B%5D=Yu-Yun%20Liu&internal%5B3%5D%5B%5D=liu%40contextsmith.com&external%5B0%5D%5B%5D=Richard%20Wang&external%5B0%5D%5B%5D=rcwang%40enfind.com&external%5B1%5D%5B%5D=Brad%20Barbin&external%5B1%5D%5B%5D=brad%40enfind.com
    ### more readable url example: .../extension/account?internal[0][]=Will Cheung&internal[0][]=wcheung@contextsmith.com&internal[1][]=Kelvin Lu&internal[1][]=klu@contextsmith.com&internal[2][]=Richard Wang&internal[2][]=rcwang@contextsmith.com&internal[3][]=Yu-Yun Liu&internal[3][]=liu@contextsmith.com&external[0][]=Richard Wang&external[0][]=rcwang@enfind.com&external[1][]=Brad Barbin&external[1][]=brad@enfind.com
    ### after Rails parses the params, params[:internal] and params[:external] are both hashes with the structure { "0" => ['Full Name', 'email@address.com'] }

    # If there are no external users specified, redirect to extension#private_domain page
    redirect_to extension_private_domain_path and return if params[:external].blank?
    external = params[:external].values.map { |person| person.map { |info| URI.unescape(info, '%2E') } }

    ex_emails = external.map { |person| person[1] }.reject { |email| get_domain(email) == current_user.organization.domain || !valid_domain?(get_domain(email)) }
    # if somehow request was made without external people or external people were filtered out due to invalid domain, redirect to extension#private_domain page
    redirect_to extension_private_domain_path and return if ex_emails.blank? 

    # group by ex_emails by domain frequency, order by most frequent domain
    ex_emails = ex_emails.group_by { |email| get_domain(email) }.values.sort_by(&:size).flatten 
    order_emails_by_domain_freq = ex_emails.map { |email| "email = '#{email}' DESC" }.join(',')
    # find all contacts within current_user org that match the external emails, in the order of ex_emails
    contacts = Contact.joins(:account).where(email: ex_emails, accounts: { organization_id: current_user.organization_id}).order(order_emails_by_domain_freq) 
    if contacts.present?
      # get all streams that these contacts are members of
      projects = contacts.joins(:visible_projects).includes(:visible_projects).map(&:projects).flatten
      if projects.present?
        # set most frequent project as stream
        @project = projects.group_by(&:id).values.max_by(&:size).first
        @account = @project.account
      end
    else
      domains = ex_emails.map { |email| get_domain(email) }.uniq
      where_domain_matches = domains.map { |domain| "email LIKE '%#{domain}'"}.join(" OR ")
      order_domain_frequency = domains.map { |domain| "email LIKE '%#{domain}' DESC"}.join(',')
      # find all contacts within current_user org that have a similar email domain to external emails, in the order of domain frequency
      contacts = Contact.joins(:account).where(accounts: { organization_id: current_user.organization_id }).where(where_domain_matches).order(order_domain_frequency)
      if contacts.blank?
        order_domain_frequency = domains.map { |domain| "domain = '#{domain}' DESC" }.join(',')
        # find all accounts within current_user org whose domain is the email domain for external emails, in the order of domain frequency
        accounts = Account.where(domain: domains, organization: current_user.organization).order(order_domain_frequency)
        # if no accounts are found that match our external email domains at this point, redirect to extension#no_account page to allow user to create this account
        redirect_to extension_no_account_path(URI.escape(domains.first, ".")) + "\?" + { internal: params[:internal], external: params[:external] }.to_param and return if @accounts.blank?
        @account = accounts.first
      end
    end
    @account ||= contacts.first.account
    @project ||= @account.projects.visible_to(current_user.organization_id, current_user.id).first

    if @project.blank?
      create_project
    elsif params[:action] == "account" 
      # extension always routes to "account" action first, don't need to run create_people for other tabs (contacts or alerts_tasks)
      # since project already exists, any new external members found should be added as suggested members, let user confirm
      create_people
    end
    
    @clearbit_domain = @account.domain? ? @account.domain : (@account.contacts.present? ? @account.contacts.first.email.split("@").last : "")
  end

  def get_account_types
    custom_lists = current_user.organization.get_custom_lists_with_options
    @account_types = !custom_lists.blank? ? custom_lists["Account Type"] : {}
  end

  def set_salesforce_user
    @salesforce_user = nil

    return if current_user.nil?

    @salesforce_base_URL = OauthUser.get_salesforce_instance_url(current_user.organization_id)

    if current_user.admin?
      # try to get salesforce production. if not connect, check if it is connected to Salesforce sandbox
      @salesforce_user = OauthUser.find_by(oauth_provider: 'salesforce', organization_id: current_user.organization_id)
      #@salesforce_user = OauthUser.find_by(oauth_provider: 'salesforcesandbox', organization_id: current_user.organization_id) if @salesforce_user.nil?
    elsif current_user.power_or_chrome_user_only?  # AND is an individual (power user or chrome user)
      @salesforce_user = OauthUser.find_by(oauth_provider: 'salesforce', organization_id: current_user.organization_id, user_id: current_user.id)
      #@salesforce_user = OauthUser.find_by(oauth_provider: 'salesforcesandbox', organization_id: current_user.organization_id, user_id: current_user.id) if @salesforce_user.nil?
    end

    @sfdc_accounts_exist = SalesforceAccount.where(contextsmith_organization_id: current_user.organization_id).limit(1).present?
    @linked_to_sfdc = @project && (!@project.salesforce_opportunity.nil? || @project.account.salesforce_accounts.present?)
    @enable_sfdc_login_and_linking = current_user.admin? || current_user.power_or_chrome_user_only?
    @enable_sfdc_refresh = @enable_sfdc_login_and_linking  # refresh and login/linking permissions can be separate in the future

    # If no SFDC accounts found, automatically refresh the SFDC accounts list
    if !@sfdc_accounts_exist && @enable_sfdc_login_and_linking
      SalesforceAccount.load_accounts(current_user.organization_id) 
      @sfdc_accounts_exist = true
    end
  end

  def create_project
    # p "*** creating project for account #{@account.name} ***"
    @project = @account.projects.new(
      name: @account.name,
      description: "Default stream for #{@account.name}",
      created_by: current_user.id,
      updated_by: current_user.id,
      owner_id: current_user.id,
      is_confirmed: true,
    )
    @project.project_members.new(user: current_user)

    # new project needs some initial external people, add them as confirmed members before loading emails/calendar from backend
    create_people(ProjectMember::STATUS[:Confirmed])

    success = @project.save
    if success
      ContextsmithService.load_emails_from_backend(@project, 2000)
      ContextsmithService.load_calendar_from_backend(@project, 1000)
    else
      redirect_to extension_project_error_path and return
    end
    success
  end

  # Helper method for creating people, used in set_account_and_project & create_project (@project should already be set before calling this)
  # By default, all internal people are added to @project as confirmed members, all external people are added to @project as suggested members
  def create_people(status=ProjectMember::STATUS[:Pending])
    if params[:internal].present?
      internal = params[:internal].values.map { |person| person.map { |info| URI.unescape(info, '%2E') } } 
      # p "*** creating new internal members for project #{@project.name} ***"
      internal.select { |person| get_domain(person[1]) == current_user.organization.domain }.each do |person|
        unless person[0] == 'me' || person[1] == current_user.email
          user = current_user.organization.users.create_with(
            first_name: get_first_name(person[0]),
            last_name: get_last_name(person[0]),
            invited_by_id: current_user.id,
            invitation_created_at: Time.current
          ).find_or_create_by(email: person[1])

          ProjectMember.create(project: @project, user: user)
        end
      end 
    end

    external = params[:external].values.map { |person| person.map { |info| URI.unescape(info, '%2E') } }
    # p "*** creating new external members for project #{@project.name} ***"
    external.reject { |person| get_domain(person[1]) == current_user.organization.domain || !valid_domain?(get_domain(person[1])) }.each do |person|
      Contact.find_or_create_from_email_info(person[1], person[0], @project, status, "Chrome")
    end
  end

  # Never trust parameters from the scary internet, only allow the white list through.
  def account_params
    params.require(:account).permit(:name, :website, :phone, :description, :address, :category, :domain)
  end
end
