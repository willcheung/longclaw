class ExtensionController < ApplicationController
  layout "extension", except: [:test, :new]

  before_action :set_account_and_project, only: [:account, :alerts_tasks, :contacts, :metrics]

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
    ex_emails = params[:external].values.map { |person| person[1] }.reject { |email| get_domain(email) == current_user.organization.domain || !valid_domain?(get_domain(email)) }
    redirect_to extension_path and return if ex_emails.blank? # if somehow request was made without external people, redirect to home page
    ex_emails = ex_emails.group_by { |email| get_domain(email) }.values.sort_by(&:size).flatten # group by ex_emails by domain frequency, order by most frequent domain
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
      # find all contacts within current_user org that have a similar email domain, in the order of domain frequency
      contacts = Contact.joins(:account).where(accounts: { organization_id: current_user.organization_id }).where(where_domain_matches).order(order_domain_frequency)
      if contacts.blank?
        order_domain_frequency = domains.map { |domain| "domain = '#{domain}' DESC" }.join(',')
        accounts = Account.where(domain: domains, organization: current_user.organization).order(order_domain_frequency)
        redirect_to extension_no_account_path(URI.escape(domains.first, ".")) + "\?" + { internal: params[:internal], external: params[:external] }.to_param and return if @accounts.blank?
        @account = accounts.first
      end
    end
    @account ||= contacts.first.account
    @project ||= @account.projects.visible_to(current_user.organization_id, current_user.id).first

    if @project.blank?
      create_project
    elsif params[:action] == "account" # extension always routes to "account" action first, don't need to run create_people for other tabs (contacts or alerts_tasks)
      create_people
    end
    
    @clearbit_domain = @account.domain? ? @account.domain : (@account.contacts.present? ? @account.contacts.first.email.split("@").last : "")
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

  def create_people(status=ProjectMember::STATUS[:Pending])
    # p "*** creating new internal members for project #{@project.name} ***"
    params[:internal].values.select { |person| get_domain(person[1]) == current_user.organization.domain }.each do |person|
      unless person[0] == 'me' || person[1] == current_user.email
        user = current_user.organization.users.create_with(
          first_name: get_first_name(person[0]),
          last_name: get_last_name(person[0]),
          invited_by_id: current_user.id,
          invitation_created_at: Time.current
        ).find_or_create_by(email: person[1])

        ProjectMember.create(project: @project, user: user)
      end
    end if params[:internal].present?

    # p "*** creating new external members for project #{@project.name} ***"
    params[:external].values.reject { |person| get_domain(person[1]) == current_user.organization.domain || !valid_domain?(get_domain(person[1])) }.each do |person|
      Contact.find_or_create_from_email_info(person[1], person[0], @project, status, "Chrome")
    end
  end

  # Never trust parameters from the scary internet, only allow the white list through.
  def account_params
    params.require(:account).permit(:name, :website, :phone, :description, :address, :category, :domain)
  end
end
