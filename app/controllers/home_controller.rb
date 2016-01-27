class HomeController < ApplicationController
  layout 'empty', only: 'access_denied'

  def index
    @metrics = {}
    previous = nil
    arr = []

    last_7d = "(CURRENT_DATE - INTERVAL '7 days')"

    @most_active_projects = Project.visible_to(current_user.organization_id, current_user.id).select("projects.*, count(distinct activities.id) as count_activities").joins(:activities).where("activities.last_sent_date > #{last_7d}").order("count_activities desc")
    #@most_active_projects = Project.visible_to(current_user.organization_id, current_user.id).select("projects.*, count(distinct activities.id) as count_activities").joins(:activities).where("activities.last_sent_date > (current_date - interval '2 years') and activities.last_sent_date < (current_date - interval '1 year')").order("count_activities desc")
    @projects_no_activities = Project.visible_to(current_user.organization_id, current_user.id) - @most_active_projects

    if !@most_active_projects.empty?
      active_project_ids = @most_active_projects.first(5).map(&:id)

      last_7d_activities = Project.count_activities_by_day(last_7d, active_project_ids)
        
      last_7d_activities.each_with_index do |p,i|
        if previous.nil?
          arr << p.count_activities
          previous = p.project_id
        else
          if previous == p.project_id
            arr << p.count_activities
          else
            @metrics[previous] = arr
            arr = []
            arr << p.count_activities
          end
          previous = p.project_id
        end

        if last_7d_activities[i+1].nil?
          @metrics[previous] = arr
        end
      end
    end
  end

  def access_denied
    # Nothing here
  end
end