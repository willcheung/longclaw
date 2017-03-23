class HomeController < ApplicationController
  layout 'empty', only: 'access_denied'
  before_action :check_user_onboarding, only: :index

  def index
    # Load all projects/streams visible to user
    visible_projects = Project.visible_to(current_user.organization_id, current_user.id).preload([:users,:contacts]).select("COUNT(DISTINCT activities.id) AS activity_count").joins("LEFT JOIN activities ON activities.project_id = projects.id").group("projects.id")
    @projects = visible_projects.owner_of(current_user.id)
    project_tasks = Notification.where(project_id: @projects.pluck(:id))
    # Unused metrics
    #@open_tasks_not_overdue = project_tasks.open.where("(original_due_date::date > ? or original_due_date is NULL) and category != '#{Notification::CATEGORY[:Alert]}'", Date.today)
    #@open_risks = project_tasks.open.risks
    @overdue_tasks = project_tasks.open.where("original_due_date::date <= ?", Date.today).where("assign_to='#{current_user.id}'")
    @open_total_tasks = project_tasks.open.where("assign_to='#{current_user.id}'")
    # Need this to show project name and user name
    @projects_reverse = @projects.map { |p| [p.id, p.name] }.to_h
    @users_reverse = get_current_org_users
    # Load all projects/streams to which the user is subscribed
    @subscribed_projects = visible_projects.select("project_subscribers.daily, project_subscribers.weekly").joins(:subscribers).where(project_subscribers: {user_id: "#{current_user.id}"}).group("project_subscribers.daily, project_subscribers.weekly").sort_by { |p| p.name.upcase }

    custom_lists = current_user.organization.get_custom_lists_with_options
    @stream_types = !custom_lists.blank? ? custom_lists["Stream Type"] : {}

    # Calculate project metrics
    unless @projects.empty? && @subscribed_projects.empty?
      project_ids_a = @projects.map(&:id) | @subscribed_projects.map(&:id)
      #@project_last_activity_date = Project.owner_of(current_user.id).includes(:activities).maximum("activities.last_sent_date")
      @metrics = Project.count_activities_by_day(7, project_ids_a)  # TODO: consider using daily_activities_last_x_days instead of count_activities_by_day
      @risk_scores = Project.new_risk_score(project_ids_a, current_user.time_zone)
      @open_risk_count = Project.open_risk_count(project_ids_a)
      @rag_status = Project.current_rag_score(project_ids_a)
      puts "risk_scores: #{@risk_scores}"
    end
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
