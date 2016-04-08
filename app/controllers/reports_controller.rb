class ReportsController < ApplicationController
  def customer
    # Load all projects visible to user
    if params[:type]
      # Filter
      account_type_filter = "accounts.category = '#{params[:type]}'"
    else
      account_type_filter = ""
    end

    @projects = Project.visible_to(current_user.organization_id, current_user.id).where(account_type_filter)

    ###### Report Data ######
    if !@projects.empty?      
      project_sum_activities = Project.find_include_sum_activities(true, 7*24, @projects.map(&:id))
      puts "============project_sum_activities============="
      puts project_sum_activities.each { |x| puts x.name, x.num_activities }
      puts "==============================================="
      @project_min = project_sum_activities.sort { |x| x.num_activities }
      @project_max = @project_min.reverse

      project_prev_sum_activities = Project.find_include_sum_activities(true, 7*24, 14*24, @projects.map(&:id))
      puts "============project_prev_sum_activities============="
      puts project_prev_sum_activities.each { |x| puts x.name, x.num_activities }
      puts "===================================================="
      project_chg_activities = Project.calculate_pct_from_prev(project_sum_activities, project_prev_sum_activities)
      puts "============project_chg_activities============="
      puts project_chg_activities.each { |x| puts x.name, x.pct_from_prev }
      puts "==============================================="
      @project_min_chg = project_chg_activities.sort { |x| x.pct_from_prev }.select { |x| x.pct_from_prev <= 0 }.reverse
      @project_max_chg = project_chg_activities.sort { |x| x.pct_from_prev }.select { |x| x.pct_from_prev > 0 }
    end
  end

  def team
  end

  def lifecycle
  end
end
