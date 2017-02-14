class ExtensionController < ApplicationController
  layout "extension", except: [:test]

  before_action :set_account_and_project, except: [:test, :index, :no_account]

  def test
    render layout: "empty"
  end

  def index
  end

  def no_account
    @domain = URI.unescape(params[:domain], '%2E')
  end

  def account
    @activities = @project.activities.take(5)
  end

  def alerts_tasks
    @notifications = @project.notifications.take(10)
  end

  def contacts
  end

  def metrics
  end

  private
  def set_account_and_project
    addresses = params[:email_addresses].split(',').map { |a| a.split('@') }
    addresses.reject! { |a| a[1] == get_domain(current_user.email) }
    redirect_to extension_path and return if addresses.blank? # if none left, show flash message? or redirect to "this is an internal communication" page
    domain = addresses.group_by { |a| a[1] }.values.max_by(&:size).first[1] # get most common domain
    @account = Account.find_by_domain(domain) # use most common domain to find account
    redirect_to extension_no_account_path(URI.escape(domain, '.')) and return unless @account # if no account, redirect to new "this acct not in contextsmith" page
    projects = @account.projects
    @project = projects.first # TODO: find best fit project from this account
  end
end
