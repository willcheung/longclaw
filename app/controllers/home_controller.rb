class HomeController < ApplicationController
  layout 'empty', only: 'access_denied'
  before_action :check_user_onboarding, only: :index

  def index
    # Load all projects visible to user
    @projects = Project.visible_to(current_user.organization_id, current_user.id)
    @projects_min_scores = Hash.new()
    project_activities = Activity.where(project_id: @projects.pluck(:id))
    project_tasks = Notification.where(project_id: @projects.pluck(:id))
    @open_tasks = project_tasks.where(is_complete: false).length
    @closed_tasks = project_tasks.where(is_complete: true, complete_date: (7.days.ago..Time.current)).length
    @open_risks = project_tasks.where(is_complete: false, category: Notification::CATEGORY[:Risk]).length
    @active_projects = 0
    # @conversations_tracked = Activity.where(project_id: @projects.pluck(:id), category: 'Conversation').length
    ###### Dashboard Metrics ######
    if !@projects.empty?
      static = Rails.env.development?
      
      project_sum_activities = Project.find_include_sum_activities(@projects.pluck(:id), 7*24)
      @active_projects = project_sum_activities.length
      # Top Active Streams
      @project_max = project_sum_activities.max_by(5) { |x| x.num_activities }
      @project_min = project_sum_activities.min_by(5) { |x| x.num_activities }

      project_prev_sum_activities = Project.find_include_sum_activities(@projects.pluck(:id), 14*24, 7*24)
      project_chg_activities = Project.calculate_pct_from_prev(project_sum_activities, project_prev_sum_activities)
      # Top Movers
      @project_max_chg = project_chg_activities.max_by(5) { |x| x.pct_from_prev }.select { |x| x.pct_from_prev >= 0 }
      @project_min_chg = project_chg_activities.min_by(5) { |x| x.pct_from_prev }.select { |x| x.pct_from_prev <= 0 }

      # How Busy Are We? Chart
      @all_activities_trend = Project.count_total_activities_by_day(current_user.organization.accounts.pluck(:id), current_user.time_zone)
      
      # Team Leaderboard
      @team_leaderboard = User.count_activities_by_user_flex(current_user.organization.accounts.pluck(:id), current_user.organization.domain, 13.days.ago.midnight.utc)
      @team_leaderboard.collect{ |u| u.email = get_full_name(User.find_by_email(u.email)) } # replace email with user full name

      # Risk Score Trend
      @projects_min_scores = Project.find_min_risk_score_by_day(@projects.pluck(:id), current_user.time_zone, static)

      # Top Risks
      projects_risk_scores = Project.current_risk_score(@projects.pluck(:id)).max_by(5) { |pid, score| score }
      projects_risks_counts = Project.count_risks_per_project(@projects.pluck(:id))
      # puts projects_risks_counts
      @top_risks = projects_risk_scores.map do |p|
        rc = projects_risks_counts.find { |r| r.id == p[0] }
        { id: p[0], risk_score: p[1], name: rc.name, open_risks: rc.open_risks }
      end
      puts @top_risks.first
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