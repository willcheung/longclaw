class ExtensionController < ApplicationController
  layout "extension", except: [:test]

  before_action :set_account_and_project, only: [:account, :alerts_tasks, :contacts, :metrics]

  def test
    render layout: "empty"
  end

  def index
  end

  def no_account
    @domain = URI.unescape(params[:domain], '%2E')
    @account = Account.new
  end

  def account
    @activities = @project.activities.take(5)
  end

  def alerts_tasks
    @notifications = @project.notifications.take(10)
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
      organization_id: current_user.organization.id,
      status: 'Active')
    )

    respond_to do |format|
      if @account.save
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
          contact = @account.contacts.create(
            first_name: get_first_name(person[1]),
            last_name: get_last_name(person[1]),
            email: person[0]
          )

          @project.project_members.new(contact: contact)
        end

        if @project.save
          ContextsmithService.load_emails_from_backend(@project, 2000)
          ContextsmithService.load_calendar_from_backend(@project, 1000)
          format.html { redirect_to extension_account_path(emails: params[:emails]), notice: 'Account Stream was successfully created.' }
          format.js { render action: 'account', status: :created, location: extension_account_path(emails: params[:emails]) }
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
    addresses = params[:emails].split(',').map { |a| a.split('@') }
    addresses.reject! { |a| a[1] == get_domain(current_user.email) }
    redirect_to extension_path and return if addresses.blank? # if none left, show flash message? or redirect to "this is an internal communication" page
    domain = addresses.group_by { |a| a[1] }.values.max_by(&:size).first[1] # get most common domain
    @account = Account.find_by_domain(domain) # use most common domain to find account
    redirect_to extension_no_account_path(domain: URI.escape(domain, '.'), emails: params[:emails], names: params[:names]) and return unless @account # if no account, redirect to new "this acct not in contextsmith" page
    projects = @account.projects
    @project = projects.first # TODO: find best fit project from this account
  end

  # Never trust parameters from the scary internet, only allow the white list through.
  def account_params
    params.require(:account).permit(:name, :website, :phone, :description, :address, :category, :domain)
  end
end
