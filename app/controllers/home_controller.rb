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
  end

  def access_denied
    # Nothing here
  end
end