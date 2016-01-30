class HomeController < ApplicationController
  layout 'empty', only: 'access_denied'

  def index
    #activities_today = Project.visible_to(current_user.organization_id, current_user.id).eager_load(:activities).where("activities.last_sent_date::date = ?", Time.now().strftime('%F')).group("activities.id")
    activities_today = Project.visible_to(current_user.organization_id, current_user.id).eager_load([:activities, :account]).where("activities.last_sent_date::date = ?", '2014-11-26').group("activities.id, accounts.id")
    @projects_with_activities_today = activities_today.group_by{|e| e.activities}

    @pinned_activities_today = Project.visible_to(current_user.organization_id, current_user.id).eager_load([:activities]).where("activities.is_pinned = true and activities.pinned_at::date = ?", '2014-11-26').group("activities.id")
  end

  def access_denied
    # Nothing here
  end
end