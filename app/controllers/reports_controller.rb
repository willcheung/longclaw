class ReportsController < ApplicationController
  def touches_by_team
    # TODO: find way to get number of projects for each user listed here
    @team_touches = User.count_activities_by_user_flex(current_user.organization.accounts.pluck(:id), current_user.organization.domain)
    @team_touches.each { |u| u.email = get_full_name(User.find_by_email(u.email)) } # replace email with user full name
  end

  def accounts_dashboard
    @projects = Project.visible_to(current_user.organization_id, current_user.id)
    risk_scores = Project.current_risk_score(@projects.pluck(:id), current_user.time_zone).sort_by { |pid, score| score }.reverse
    total_risk_scores = 0
    @risk_scores = risk_scores.map do |r|
      proj = @projects.find { |p| p.id == r[0] }
      total_risk_scores += r[1]
      Hashie::Mash.new({ id: proj.id, score: r[1], name: proj.name })
    end
    @average_risk_score = (total_risk_scores.to_f/@risk_scores.length).round(1)
  end

  def account_data
    @account = Project.find(params[:id])
    @risk_score = @account.current_risk_score(current_user.time_zone)
    @open_risks_count = @account.notifications.where(is_complete: false, category: Notification::CATEGORY[:Risk]).count
    @last_activity_date = @account.activities.conversations.maximum("activities.last_sent_date")
    @risk_score_trend = Project.find_min_risk_score_by_day([params[:id]], current_user.time_zone)
    
    # Engagement Volume Chart
    # TODO: Generate data for Engagement Volume Chart in SQL query   
    activities_by_category = @account.activities.where(last_sent_date: 14.days.ago.midnight..Time.current.midnight).select { |a| a.is_visible_to(current_user) }.reverse.group_by { |a| a.category }
    @activities_by_category_date = {}
    activities_by_category.each do |category, activities|
      temp_activities_by_date = Array.new(14, 0)
      # temp_activities_by_date based on number of days since 14 days ago
      activities.each do |a|
        day_index = (a.last_sent_date - 14.days.ago.midnight).floor/(60*60*24)
        temp_activities_by_date[day_index] += 1
      end
      @activities_by_category_date[category] = temp_activities_by_date
    end

    # TODO: Generate data for Risk Volume Chart in SQL query
    # Risk Volume Chart
    risk_notifications = @account.notifications.risks.where(created_at: 14.days.ago.midnight..Time.current.midnight)
    @risks_by_date = Array.new(14, 0)
    risk_notifications.each do |r|
      # risks_by_date based on number of days since 14 days ago
      day_index = (r.created_at - 14.days.ago.midnight).floor/(60*60*24)
      @risks_by_date[day_index] += 1
    end

    # TODO: Modify query and method params for count_activities_by_user_flex to take project_ids instead of account_ids
    # Most Active Contributors & Activities By Team
    user_num_activities = User.count_activities_by_user_flex([@account.account.id], current_user.organization.domain)
    @team_leaderboard = []
    @activities_by_dept = Hash.new(0)
    activities_by_dept_total = 0
    user_num_activities.each do |u|
      user = User.find_by_email(u.email)
      u.email = get_full_name(user) if user
      @team_leaderboard << u
      dept = user.nil? || user.department.nil? ? '(unknown)' : user.department
      @activities_by_dept[dept] += u.inbound_count + u.outbound_count
      activities_by_dept_total += u.inbound_count + u.outbound_count
    end
    # Convert Activities By Team to %
    @activities_by_dept.each { |dept, count| @activities_by_dept[dept] = (count.to_f/activities_by_dept_total*100).round(1)  }
    # Only show top 5 for Most Active Contributors
    @team_leaderboard = @team_leaderboard[0...5]

    render layout: false
  end

  def accounts
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
    @project_all_touches = []
    @project_all_chg_touches = []
    ###### Report Data ######
    if !@projects.empty?
      # equivalent to Project.find_include_sum_activities(7*24, @projects.map(&:id))
      # @project_all_touches = Project.find_include_sum_activities(0, static, 90*24, @projects.map(&:id))
      # sorted high to low by num_activities
      # @project_all_touches.sort! { |x, y| x.num_activities.to_i <=> y.num_activities.to_i }.reverse!

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
