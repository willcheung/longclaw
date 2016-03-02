class HomeController < ApplicationController
  layout 'empty', only: 'access_denied'

  def index
    d_tz =  params[:date] || Time.current.strftime('%F')
    @date_with_timezone = Date.parse(d_tz)
    date_filter_offset = Time.current.seconds_since_midnight

    if Date.current <= @date_with_timezone
      where = " between (current_timestamp - interval '#{date_filter_offset} seconds') and current_timestamp"
    else
      where = " between to_timestamp(#{Time.zone.parse(d_tz).utc.to_i}) and (to_timestamp(#{Time.zone.parse(d_tz).utc.to_i}) + interval '24 hours')"
    end

    activities_today = Project.visible_to(current_user.organization_id, current_user.id).eager_load([:activities, :account]).where("activities.last_sent_date" + where).group("activities.id, accounts.id")
    @projects_with_activities_today = activities_today.group_by{|e| e.activities}

    @pinned_activities_today = Project.visible_to(current_user.organization_id, current_user.id).eager_load([:activities]).where("activities.is_pinned = true and activities.pinned_at" + where).group("activities.id")
    
    ###### Dashboard Metrics ######
    # Load all projects visible to user
    @project_most_activities_pct_chg = {}
    @project_least_activities_pct_chg = {}

    projects = Project.visible_to(current_user.organization_id, current_user.id).group("accounts.id")
    projects_with_activities_count_7d = Project.count_num_activities(7*24, projects.map(&:id))
    
    @project_most_activities = projects_with_activities_count_7d.max_by(&:num_activities)
    @project_least_activities = projects_with_activities_count_7d.min_by(&:num_activities)
    @project_biggest_change = projects_with_activities_count_7d.max_by {|x| x.percent_change_from_daily_avg.abs}
  end

  def access_denied
    # Nothing here
  end
end