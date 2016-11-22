class ReportsController < ApplicationController
  def touches_by_team
    # TODO: find way to get number of projects for each user listed here
    @team_touches = User.count_activities_by_user_flex(current_user.organization.accounts.pluck(:id), current_user.organization.domain)
    @team_touches.each { |u| u.email = get_full_name(User.find_by_email(u.email)) } # replace email with user full name
  end

  def accounts_dashboard
    projects = Project.visible_to(current_user.organization_id, current_user.id)
    risk_scores = Project.current_risk_score(projects.pluck(:id), current_user.time_zone).sort_by { |pid, score| score }.reverse
    total_risk_scores = 0
    @risk_scores = risk_scores.map do |r|
      proj = projects.find { |p| p.id == r[0] }
      total_risk_scores += r[1]
      Hashie::Mash.new({ id: proj.id, score: r[1], name: proj.name })
    end
    @average_risk_score = (total_risk_scores.to_f/risk_scores.length).round(1)
  end

  def dashboard_data
    @sort = params[:sort]

    projects = Project.visible_to(current_user.organization_id, current_user.id)
    projects = projects.where(category: params[:category]) if params[:category]
    projects = projects.joins(:account).where(accounts: { category: params[:account] }) if params[:account]
    @data = [] and return if projects.blank?

    case @sort
    when "Risk Score Today"
      risk_scores = Project.current_risk_score(projects.pluck(:id), current_user.time_zone).sort_by { |pid, score| score }.reverse
      total_risk_scores = 0
      @data = risk_scores.map do |r|
        proj = projects.find { |p| p.id == r[0] }
        total_risk_scores += r[1]
        color = r[1] >= 80 ? 'highRisk' : r[1] >= 60 ? 'mediumRisk' : 'lowRisk'
        Hashie::Mash.new({ id: proj.id, name: proj.name, y: r[1], color: color })
      end
      @average_risk_score = (total_risk_scores.to_f/risk_scores.length).round(1)
    when "Days Inactive"
      last_sent_dates = projects.includes(:activities).maximum("activities.last_sent_date").sort_by { |pid, date| date.nil? ? Time.current : date }
      @data = last_sent_dates.map do |d|
        proj = projects.find { |p| p.id == d[0] }
        y = d[1].nil? ? 0 : Date.current.mjd - d[1].in_time_zone.to_date.mjd
        Hashie::Mash.new({ id: proj.id, name: proj.name, y: y, color: 'blue' })
      end
    when "Engagement Last 7d"
      project_engagement = Project.find_include_sum_activities(projects.pluck(:id), 7*24)
      @data = project_engagement.map do |p|
        Hashie::Mash.new({ id: p.id, name: p.name, y: p.num_activities, color: 'blue'})
      end
    when "Risk / Engagement %"
      project_engagement = Project.find_include_sum_activities(projects.pluck(:id))
      project_risks = projects.select("COUNT(DISTINCT notifications.id) AS risk_count").joins("LEFT JOIN notifications ON notifications.project_id = projects.id AND notifications.category = '#{Notification::CATEGORY[:Risk]}'").group("projects.id")
      @data = project_engagement.map do |e|
        risk = project_risks.find { |r| r.id == e.id }
        Hashie::Mash.new({ id: e.id, name: e.name, y: (risk.risk_count.to_f/e.num_activities*100).round(2), color: 'blue'})
      end
      @data.sort_by! { |d| d.y }.reverse!
    when "Total Open Risks"
      open_risk_counts = Project.count_risks_per_project(projects.pluck(:id))
      @data = open_risk_counts.map do |r|
        Hashie::Mash.new({ id: r.id, name: r.name, y: r.open_risks, color: 'blue'})
      end
    when "Total Overdue Tasks"
      overdue_tasks = projects.select("COUNT(DISTINCT notifications.id) AS task_count").joins("LEFT JOIN notifications ON notifications.project_id = projects.id AND notifications.is_complete IS FALSE AND EXTRACT(EPOCH FROM notifications.original_due_date) < #{Time.current.to_i}").group("projects.id").order("task_count DESC")
      @data = overdue_tasks.map do |t|
        Hashie::Mash.new({ id: t.id, name: t.name, y: t.task_count, color: 'blue'})
      end
    else # Invalid
      @data = []
    end
  end

  def account_data
    @account = Project.find(params[:id])
    @risk_score = @account.current_risk_score(current_user.time_zone)
    @open_risks_count = @account.notifications.open.risks.count
    @last_activity_date = @account.activities.conversations.maximum("activities.last_sent_date")
    @risk_score_trend = Project.find_min_risk_score_by_day([params[:id]], current_user.time_zone)
    
    # Engagement Volume Chart
    @activities_by_category_date = @account.daily_activities_last_x_days(current_user.time_zone).group_by { |a| a.category }

    # TODO: Generate data for Risk Volume Chart in SQL query
    # Risk Volume Chart
    risk_notifications = @account.notifications.risks.where(created_at: 14.days.ago.midnight..Time.current.midnight)
    @risks_by_date = Array.new(14, 0)
    risk_notifications.each do |r|
      # risks_by_date based on number of days since 14 days ago
      day_index = r.created_at.to_date.mjd - 14.days.ago.midnight.to_date.mjd
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
    # Placeholder stuff from home_controller
    # Load all projects visible to user
    @projects = Project.visible_to(current_user.organization_id, current_user.id)
    @projects_min_scores = Hash.new()
    project_tasks = Notification.where(project_id: @projects.pluck(:id))
    @open_tasks = project_tasks.open.count
    @closed_tasks = project_tasks.where(is_complete: true, complete_date: (7.days.ago..Time.current)).count
    @open_risks = project_tasks.open.risks.count
    @overdue_tasks = project_tasks.where("is_complete = false and original_due_date::date < ?", Date.today).count

    ###### Dashboard Metrics ######
    if !@projects.empty?
      
      project_sum_activities = Project.find_include_sum_activities(@projects.pluck(:id), 7*24)

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
      @team_leaderboard = User.count_activities_by_user_flex(current_user.organization.accounts.pluck(:id), current_user.organization.domain)
      @team_leaderboard.collect{ |u| u.email = get_full_name(User.find_by_email(u.email)) } # replace email with user full name

      # Risk Score Trend
      @projects_min_scores = Project.find_min_risk_score_by_day(@projects.pluck(:id), current_user.time_zone)

      # Top Risks
      projects_risk_scores = Project.current_risk_score(@projects.pluck(:id), current_user.time_zone).sort_by { |pid, score| score }.reverse[0...5]
      ### NOT using built in Ruby max_by function due to bug
      projects_risks_counts = Project.count_risks_per_project(@projects.pluck(:id))
      @top_risks = projects_risk_scores.map do |p|
        rc = projects_risks_counts.find { |r| r.id == p[0] }
        { id: p[0], risk_score: p[1], name: rc.name, open_risks: rc.open_risks }
      end
    end
  end

  def lifecycle
  end
end
