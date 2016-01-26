class HomeController < ApplicationController
  layout 'empty', only: 'access_denied'

  def index
    @most_active_projects = Project.visible_to(current_user.organization_id, current_user.id).select("projects.*, count(distinct activities.id) as count_activities").joins(:activities).where("activities.last_sent_date > (current_date - interval '7 days')").order("count_activities desc")
    @projects_no_activities = Project.visible_to(current_user.organization_id, current_user.id) - @most_active_projects
  end

  def access_denied
    # Nothing here
  end
end