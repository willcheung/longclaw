class HomeController < ApplicationController
  layout false, only: ['landing','privacy','terms']
  before_action :check_user_onboarding, only: :index
  before_action :get_current_org_users, only: :index
  before_action :get_current_org_opportunity_stages, only: :index
  before_action :get_current_org_opportunity_forecast_categories, only: :index
  before_action :home_filter_state, only: [:index]

  def index
    # @MEMBERS_LIST_LIMIT = 8 # Max number of Opportunity members to show in mouse-over tooltip

    # Load all projects/opportunities visible to user, belongs to user, and to which user is subscribed
    visible_projects = Project.visible_to(current_user.organization_id, current_user.id)
    visible_projects = visible_projects.close_date_within(params[:close_date]) unless params[:close_date] == 'Any'
    visible_projects = visible_projects.where.not(stage: current_user.organization.get_closed_stages) if params[:close_date] == Project::CLOSE_DATE_RANGE[:ThisQuarterOpen]
    @current_user_projects = visible_projects.owner_of(current_user.id).select("projects.*, false AS daily, false AS weekly")
    subscribed_projects = visible_projects.select("project_subscribers.daily, project_subscribers.weekly").joins(:subscribers).where(project_subscribers: {user_id: current_user.id}).group("project_subscribers.daily, project_subscribers.weekly")

    # Load notifications for "My Alerts & Tasks"
    unless @current_user_projects.blank?
      project_tasks = Notification.where(project_id: @current_user_projects.pluck(:id))
      @open_total_tasks = project_tasks.open.where("assign_to='#{current_user.id}'").sort_by{|t| t.original_due_date.blank? ? Time.at(0) : t.original_due_date }.reverse
      # Need these to show project name and user name instead of pid and uid
      @projects_reverse = @current_user_projects.map { |p| [p.id, p.name] }.to_h
    end

    # Load project data for "My Opportunities"
    @projects = (subscribed_projects + @current_user_projects).uniq(&:id).sort_by{|p| p.name.upcase} # projects/opportunities user owns or to which user is subscribed
    unless @projects.empty?
      project_ids_a = @projects.map(&:id)

      @sparkline = Project.count_activities_by_day_sparkline(project_ids_a, current_user.time_zone)
      @risk_scores = Project.new_risk_score(project_ids_a, current_user.time_zone)
      @open_risk_count = Project.open_risk_count(project_ids_a)
      # @days_to_close = Project.days_to_close(project_ids_a)
      @project_days_inactive = visible_projects.joins(:activities).where.not(activities: { category: [Activity::CATEGORY[:Note], Activity::CATEGORY[:Alert], Activity::CATEGORY[:NextSteps]] }).where('activities.last_sent_date <= ?', Time.current).maximum("activities.last_sent_date") # get last_sent_date
      @project_days_inactive.each { |pid, last_sent_date| @project_days_inactive[pid] = Time.current.to_date.mjd - last_sent_date.in_time_zone.to_date.mjd } # convert last_sent_date to days inactive
      @next_meetings = Activity.meetings.next_week.select("project_id, min(last_sent_date) as next_meeting").where(project_id: project_ids_a).group("project_id")
      @next_meetings = Hash[@next_meetings.map { |p| [p.project_id, p.next_meeting] }]

      #@rag_status = Project.current_rag_score(project_ids_a)
    end

    # Unused metrics
    #@open_tasks_not_overdue = project_tasks.open.where("(original_due_date::date > ? or original_due_date is NULL) and category != '#{Notification::CATEGORY[:Alert]}'", Date.today)
    #@open_risks = project_tasks.open.alerts
    #@overdue_tasks = project_tasks.open.where("original_due_date::date <= ?", Date.today).where("assign_to='#{current_user.id}'")

    #p params
  end

  def daily_summary
    d_tz =  params[:date] || Time.current.strftime('%F')
    @date_with_timezone = Date.parse(d_tz)
    date_filter_offset = Time.current.seconds_since_midnight

    if Date.current <= @date_with_timezone
      where = " between (current_timestamp - interval '#{date_filter_offset} seconds') and current_timestamp"
    else
      where = " between to_timestamp(#{Time.zone.parse(d_tz).utc.to_i}) and (to_timestamp(#{Time.zone.parse(d_tz).utc.to_i}) + interval '24 hours')"
    end

    @sub = current_user.subscriptions.includes(:project)

    if !@sub.nil? and !@sub.empty?
      activities_today = Project.visible_to(current_user.organization_id, current_user.id).following_daily(current_user.id).eager_load([:activities, :account]).where("activities.last_sent_date" + where).group("activities.id, accounts.id")
      @projects_with_activities_today = activities_today.group_by{|e| e.activities.select {|a| a.is_visible_to(current_user) }}

      pinned_activities_today = Project.visible_to(current_user.organization_id, current_user.id).eager_load([:activities]).where("activities.is_pinned = true and activities.pinned_at" + where).group("activities.id")
      @pinned_activities_today = pinned_activities_today.collect { |x| x.activities.select {|a| a.is_visible_to(current_user) }}.flatten
    end
  end

  def access_denied
    render :layout => 'empty'
    # @extension_downloaded = true
    @extension_downloaded = request.user_agent.downcase.match(/chrome/) && cookies[:chromeNotificationBar] == 'false'
    # in case a Basic user signs up through main page, force sign out here so that they will sign in through extension and trigger onboarding
    if current_user.present? && current_user.onboarding_step == Utils::ONBOARDING[:fill_in_info]
      sign_out current_user
    end
  end

  private

  def check_user_onboarding
    if current_user.onboarding_step == Utils::ONBOARDING[:confirm_projects] and !current_user.cluster_create_date.nil?
      redirect_to onboarding_confirm_projects_path
    elsif current_user.onboarding_step == Utils::ONBOARDING[:confirm_projects] and current_user.cluster_create_date.nil?
      redirect_to onboarding_creating_clusters_path
    end
  end

  def home_filter_state
    if params[:close_date]
      cookies[:home_close_date] = {value: params[:close_date]}
    else
      params[:close_date] = cookies[:home_close_date] ? cookies[:home_close_date] : Project::CLOSE_DATE_RANGE[:ThisQuarterOpen]
    end
  end
end
