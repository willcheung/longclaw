class ReportsController < ApplicationController
  def touches_by_team
    @team_leaderboard = User.count_activities_by_user_flex(current_user.organization.accounts.map(&:id), current_user.organization.domain, 7.days.ago.utc)
    @team_leaderboard.collect{ |u| u.email = get_full_name(User.find_by_email(u.email)) } # replace email with user full name
  end

  def customer
    # if params[:type]
    #   # Filter
    #   account_type_filter = "accounts.category = '#{params[:type]}'"
    # else
    #   account_type_filter = ""
    # end
    # @projects = Project.visible_to(current_user.organization_id, current_user.id).where(account_type_filter)



    # set static boolean based on environment and pass to find_include_sum_activities
    static = Rails.env.development?
    # Load all projects visible to user
    @projects = Project.visible_to(current_user.organization_id, current_user.id)
    ###### Report Data ######
    if !@projects.empty?
      # equivalent to Project.find_include_sum_activities(7*24, @projects.map(&:id))
      @project_all_touches = Project.find_include_sum_activities(0, static, 90*24, @projects.map(&:id))
      # sorted high to low by num_activities
      @project_all_touches.sort! { |x, y| x.num_activities.to_i <=> y.num_activities.to_i }.reverse!

      # project_prev_all_touches = Project.find_include_sum_activities(7*24, static, 14*24, @projects.map(&:id))
      # project_chg_activities = Project.calculate_pct_from_prev(@project_all_touches, project_prev_all_touches)
      # # sorted high to low by pct_from_prev
      # project_chg_activities.sort! { |x, y| x.pct_from_prev.to_f <=> y.pct_from_prev.to_f }.reverse!
      # if project_chg_activities.length > 10
      #   # take first and last 5 from sorted array == most /least
      #   project_chg_activities_top = project_chg_activities[0, 5]
      # else
      #   project_chg_activities_top = project_chg_activities
      # end
      # @project_top_chg_touches = {}
      # @project_top_chg_touches[:pos] = project_chg_activities_top.select { |x| x.pct_from_prev > 0 }
      # @project_top_chg_touches[:no] = project_chg_activities_top.select { |x| x.pct_from_prev == 0 }
      # @project_top_chg_touches[:neg] = project_chg_activities_top.select { |x| x.pct_from_prev < 0 }

      # @project_all_chg_touches = {}
      # @project_all_chg_touches[:pos] = project_chg_activities.select { |x| x.pct_from_prev > 0 }
      # @project_all_chg_touches[:no] = project_chg_activities.select { |x| x.pct_from_prev == 0 }
      # @project_all_chg_touches[:neg] = project_chg_activities.select { |x| x.pct_from_prev < 0 }
    end
  end

  def team
  end

  def lifecycle
  end
end
