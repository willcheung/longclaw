class HomeController < ApplicationController
  layout 'empty', only: 'access_denied'
  before_action :check_user_onboarding, only: :index

  def index
    @MEMBERS_LIST_LIMIT = 8 # Max number of Opportunity members to show in mouse-over tooltip

    # Load all projects/opportunity visible to user
    visible_projects = Project.visible_to(current_user.organization_id, current_user.id)
    current_user_projects = visible_projects.owner_of(current_user.id).select("projects.*, false AS daily, false AS weekly")

    project_tasks = Notification.where(project_id: current_user_projects.pluck(:id))
    @open_total_tasks = project_tasks.open.where("assign_to='#{current_user.id}'").sort_by{|t| t.original_due_date.blank? ? Time.at(0) : t.original_due_date }.reverse
    # Need this to show project name and user name
    @projects_reverse = current_user_projects.map { |p| [p.id, p.name] }.to_h
    @users_reverse = get_current_org_users

    # Load all projects/opportunity to which the user is subscribed
    subscribed_projects = visible_projects.select("project_subscribers.daily, project_subscribers.weekly").joins(:subscribers).where(project_subscribers: {user_id: current_user.id}).group("project_subscribers.daily, project_subscribers.weekly")

    @projects = current_user_projects
    subscribed_projects.each do |p|
      pid = @projects.find {|s| s.id == p.id}
      @projects << p if pid.nil?
    end
    @projects = @projects.sort_by{|p| p.name.upcase}
   
    # Calculate project metrics
    unless @projects.empty?
      project_ids_a = @projects.map(&:id)

      @sparkline = Project.count_activities_by_day_sparkline(project_ids_a, current_user.time_zone)
      @risk_scores = Project.new_risk_score(project_ids_a, current_user.time_zone)
      @open_risk_count = Project.open_risk_count(project_ids_a)
      @days_to_close = Project.days_to_close(project_ids_a)
      @project_days_inactive = visible_projects.joins(:activities).where.not(activities: { category: [Activity::CATEGORY[:Note], Activity::CATEGORY[:Alert]] }).maximum("activities.last_sent_date") # get last_sent_date
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
    # Nothing here
  end

  private

  def check_user_onboarding
    if current_user.onboarding_step == Utils::ONBOARDING[:confirm_projects] and !current_user.cluster_create_date.nil?
      redirect_to onboarding_confirm_projects_path
    elsif current_user.onboarding_step == Utils::ONBOARDING[:confirm_projects] and current_user.cluster_create_date.nil?
      redirect_to onboarding_creating_clusters_path
    end
  end
end
