class HomeController < ApplicationController
  layout 'empty', only: 'access_denied'
  before_action :check_user_onboarding, only: :index

  def index
    # Load all projects visible to user

    @projects = Project.visible_to(current_user.organization_id, current_user.id)
    @projects_min_scores = Hash.new()
    project_activities = Activity.where(project_id: @projects.pluck(:id))
    visible_activities = project_activities.select { |a| a.is_visible_to(current_user) }
    @open_tasks = Notification.where(project_id: @projects.pluck(:id), is_complete: false).select do |n| 
      n.conversation_id.nil? || 
      visible_activities.any? {|a| n.project_id == a.project_id && n.conversation_id == a.backend_id } ||
      !project_activities.any? {|a| n.conversation_id == a.backend_id }
    end.length
    @closed_tasks = Notification.where(project_id: @projects.pluck(:id), is_complete: true, complete_date: (7.days.ago..Time.current), conversation_id: visible_activities.map(&:backend_id)).length
    @active_projects = 0
    @conversations_tracked = Activity.where(project_id: @projects.pluck(:id), category: 'Conversation').length
    ###### Dashboard Metrics ######
    if !@projects.empty?
      # static = Rails.env.development?
      static = false
      
      project_sum_activities = Project.find_include_sum_activities(0, static, 7*24, @projects.pluck(:id))
      @active_projects = project_sum_activities.length
      @project_max = project_sum_activities.max_by(5) { |x| x.num_activities }
      @project_min = project_sum_activities.min_by(5) { |x| x.num_activities }

      project_prev_sum_activities = Project.find_include_sum_activities(7*24, static, 14*24, @projects.pluck(:id))
      project_chg_activities = Project.calculate_pct_from_prev(project_sum_activities, project_prev_sum_activities)
      @project_max_chg = project_chg_activities.max_by(5) { |x| x.pct_from_prev }.select { |x| x.pct_from_prev >= 0 }
      @project_min_chg = project_chg_activities.min_by(5) { |x| x.pct_from_prev }.select { |x| x.pct_from_prev <= 0 }

      @project_trend = Project.find_and_count_activities_by_day(@projects.pluck(:id), current_user.time_zone)

      # How Busy Are We? Chart
      @all_activities_trend = Project.count_total_activities_by_day(current_user.organization.accounts.pluck(:id), current_user.time_zone)
      
      # @team_leaderboard = User.count_activities_by_user(current_user.organization.accounts.pluck(:id), current_user.organization.domain, current_user.time_zone)
      @team_leaderboard = User.count_activities_by_user_flex(current_user.organization.accounts.pluck(:id), current_user.organization.domain, 13.days.ago.midnight.utc)
      @team_leaderboard.collect{ |u| u.email = get_full_name(User.find_by_email(u.email)) } # replace email with user full name

      @projects_min_scores = Project.find_min_risk_score_by_day(@projects.pluck(:id), current_user.time_zone, static)
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
      activities_today = Project.visible_to(current_user.organization_id, current_user.id).following(current_user.id).eager_load([:activities, :account]).where("activities.last_sent_date" + where).group("activities.id, accounts.id")
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