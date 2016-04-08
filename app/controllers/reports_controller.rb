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
      @project_sum_activities = Project.find_include_sum_activities(true, 7*24, @projects.map(&:id))
      # sorted low to high by num_activities
      @project_sum_activities.sort! { |x, y| x.num_activities.to_i <=> y.num_activities.to_i }.reverse!

      project_prev_sum_activities = Project.find_include_sum_activities(true, 7*24, 14*24, @projects.map(&:id))
      project_chg_activities = Project.calculate_pct_from_prev(@project_sum_activities, project_prev_sum_activities)
      # sorted low to high by pct_from_prev
      @project_neg_chg = project_chg_activities.sort { |x, y| x.pct_from_prev.to_f <=> y.pct_from_prev.to_f }.select { |x| x.pct_from_prev < 0 }.reverse
      @project_no_chg = project_chg_activities.select { |x| x.pct_from_prev == 0 }
      @project_pos_chg = project_chg_activities.sort { |x, y| x.pct_from_prev.to_f <=> y.pct_from_prev.to_f }.select { |x| x.pct_from_prev > 0 }.reverse
      puts "===="
      project_chg_activities.each { |x| puts x.name, x.pct_from_prev }
      puts "===="
      puts "===="
      @project_pos_chg.each { |x| puts x.name, x.pct_from_prev }
      puts "===="
    end
  end

  def team
  end

  def lifecycle
  end
end
