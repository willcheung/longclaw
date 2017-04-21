class ExtensionController < ApplicationController
  layout "extension", except: [:test, :new]

  before_action :set_account_and_project, only: [:account, :alerts_tasks, :contacts, :metrics]
  before_action :set_salesforce_user, only: [:account]

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

  def account
    @activities = @project.activities.visible_to(current_user.email).take(8)
    @salesforce_base_URL = OauthUser.get_salesforce_instance_url(current_user.organization_id)
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
          format.html { redirect_to extension_account_path(emails: params[:emails]), notice: 'Account Stream was successfully created.' }
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
    # TODO: blacklist gmail, yahoo, hotmail, etc.
    addresses = params[:emails].split(',').reject { |a| get_domain(a) == get_domain(current_user.email) }
    redirect_to extension_path and return if addresses.blank? # if none left, show flash message? or redirect to "this is an internal communication" page
    addresses = addresses.group_by { |a| get_domain(a) }.values.sort_by(&:size).flatten # group by addresses by domain frequency, most frequent domain first
    order_addresses_by_domain_freq = addresses.map { |a| "email = '#{a}' DESC" }.join(',')
    contacts = Contact.joins(:account).where(email: addresses, accounts: { organization_id: current_user.organization_id}).order(order_addresses_by_domain_freq) #.includes(:projects, :account)
    if contacts.present?
      projects = contacts.joins(:visible_projects).includes(:visible_projects).map(&:projects).flatten
      if projects.present?
        @project = projects.group_by(&:id).values.max_by(&:size).first
        @account = @project.account
      end
    else
      domains = addresses.map { |a| get_domain(a) }.uniq
      where_domain_matches = domains.map { |domain| "email LIKE '%#{domain}'"}.join(" OR ")
      order_domain_frequency = domains.map { |domain| "email LIKE '%#{domain}' DESC"}.join(',')
      contacts = Contact.joins(:account).where(accounts: { organization_id: current_user.organization_id }).where(where_domain_matches).order(order_domain_frequency)
      if contacts.blank?
        order_domain_frequency = domains.map { |domain| "domain = '#{domain}' DESC" }.join(',')
        accounts = Account.where(domain: domains, organization: current_user.organization).order(order_domain_frequency)
        redirect_to extension_no_account_path(URI.escape(domains.first, ".")) + "\?" + { emails: params[:emails], names: params[:names] }.to_param and return if @accounts.blank?
        @account = accounts.first
      end
    end
    @account ||= contacts.first.account
    @project ||= @account.projects.where(status: "Active").first
    create_project if @project.blank?

    @clearbit_domain = @account.domain? ? @account.domain : (@account.contacts.present? ? @account.contacts.first.email.split("@").last : "")
  end

  def create_project
    @project = @account.projects.new(
      name: @account.name,
      description: "Default stream for #{@account.name}",
      created_by: current_user.id,
      updated_by: current_user.id,
      owner_id: current_user.id,
      is_confirmed: true,
    )
    @project.project_members.new(user: current_user)

    emails = params[:emails].split(',')
    names = params[:names].split(',')
    emails.zip(names) do |person|
      unless person[1] == 'me' || person[0] == current_user.email
        if get_domain(person[0]) == get_domain(current_user.email)
          user = current_user.organization.users.create_with(
            first_name: get_first_name(person[1]),
            last_name: get_last_name(person[1]),
            invited_by_id: current_user.id,
            invitation_created_at: Time.current
          ).find_or_create_by(email: person[0])

          @project.project_members.new(user: user)
        else
          contact = @account.contacts.create_with(
            first_name: get_first_name(person[1]),
            last_name: get_last_name(person[1])
          ).find_or_create_by(email: person[0])

          @project.project_members.new(contact: contact)
        end
      end
    end

    success = @project.save
    if success
      ContextsmithService.load_emails_from_backend(@project, 2000)
      ContextsmithService.load_calendar_from_backend(@project, 1000)
    else
      redirect_to extension_project_error_path and return
    end
    success
  end

  def set_salesforce_user
    @salesforce_user = nil
    if current_user.admin?
      puts "#{current_user.first_name} is admin!"
      # try to get salesforce production. if not connect, check if it is connected to Salesforce sandbox
      @salesforce_user = OauthUser.find_by(oauth_provider: 'salesforce', organization_id: current_user.organization_id)
      #@salesforce_user = OauthUser.find_by(oauth_provider: 'salesforcesandbox', organization_id: current_user.organization_id) if @salesforce_user.nil?
    elsif current_user.power_or_chrome_user_only?  # AND is an individual (power user or chrome user)
      puts "#{current_user.first_name} is a Power or Chrome user!"
      @salesforce_user = OauthUser.find_by(oauth_provider: 'salesforce', organization_id: current_user.organization_id, user_id: current_user.id)
      #@salesforce_user = OauthUser.find_by(oauth_provider: 'salesforcesandbox', organization_id: current_user.organization_id, user_id: current_user.id) if @salesforce_user.nil?
    end
    puts "@salesforce_user=#{@salesforce_user}" 
    session[:return_to] = request.fullpath  #for redirecting back to this page after Salesforce auth callback
  end

  # Never trust parameters from the scary internet, only allow the white list through.
  def account_params
    params.require(:account).permit(:name, :website, :phone, :description, :address, :category, :domain)
  end
end
