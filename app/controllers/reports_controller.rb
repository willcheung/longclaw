class ReportsController < ApplicationController
  before_action :get_owners_in_org, only: [:accounts_dashboard, :ad_sort_data]

  ACCOUNT_DASHBOARD_METRIC = { :activities_last14d => "Activities (Last 14d)", :days_inactive => "Days Inactive", :open_alerts => "Total Open Alerts", :overdue_tasks => "Total Overdue Tasks", :deal_size => "Deal Size", :days_to_close => "Days to Close"} # Removed: :risk_score => "Risk Score"
  TEAM_DASHBOARD_METRIC = { :activities_last14d => "Activities (Last 14d)", :time_spent_last14d => "Time Spent (Last 14d)", :opportunities => "Opportunities", :new_alerts_and_tasks_last14d => "New Alerts & Tasks (Last 14d)", :closed_alerts_and_tasks_last14d => "Closed Alerts & Tasks (Last 14d)", :open_alerts_and_tasks => "Open Alerts & Tasks"}

  # "accounts_dashboard" is actually referring to opportunities, AKA projects
  def accounts_dashboard
    custom_lists = current_user.organization.get_custom_lists_with_options
    @account_types = !custom_lists.blank? ? custom_lists["Account Type"] : {}
    @opportunity_types = !custom_lists.blank? ? custom_lists["Opportunity Type"] : {}

    params[:sort] = ACCOUNT_DASHBOARD_METRIC[:activities_last14d]
    ad_sort_data
  end

  def team_dashboard
    users = current_user.organization.users
    @departments = users.pluck(:department).compact.uniq
    @titles = users.pluck(:title).compact.uniq

    params[:sort] = TEAM_DASHBOARD_METRIC[:activities_last14d]
    td_sort_data
  end

  # for loading metrics data (left panel) on Team Dashboard
  def td_sort_data
    @metric = params[:sort]
    @metric_tick_interval = getTickIntervalForMetric(@metric)
    users = current_user.organization.users
    
    # Incrementally apply filters
    if params[:team].present?
      if params[:team] == "none"
        users = users.where(department: nil)
      else
        users = users.where(department: params[:team])
      end
    end

    if params[:title].present?
      if params[:title] == "none"
        users = users.where(title: nil)
      else
        users = users.where(title: params[:title])
      end
    end

    @data = [] and return if users.blank?  #quit early if all projects are filtered out

    case @metric
    when TEAM_DASHBOARD_METRIC[:activities_last14d]
      user_activities = User.count_all_activities_by_user(current_user.organization.accounts.ids, users.ids).group_by { |u| u.id }
      @data = [] and @categories = [] and return if user_activities.blank?

      @data = user_activities.map do |uid, activities|
        user = users.find { |usr| usr.id == uid }
        Hashie::Mash.new({ id: user.id, name: get_full_name(user), y: activities, total: activities.sum(&:num_activities) })
      end
      #@data = @data.select {|a| a.total > 0}

      @categories = @data.inject([]) do |memo, p|
        memo | p.y.select {|a| a.num_activities > 0}.map(&:category)
      end  # get (and show in legend) only categories that have data
    when TEAM_DASHBOARD_METRIC[:time_spent_last14d]
      account_ids = current_user.organization.accounts.ids
      user_emails = current_user.organization.users.pluck(:email)
      @data = [] and @categories = [] and return if account_ids.blank? || user_emails.blank?
      email_time = User.team_usage_report(account_ids, user_emails)
      meeting_time = User.meeting_report(account_ids, user_emails)
      @data = users.map do |user|
        email_t = email_time.find { |et| et.email == user.email }
        if email_t.nil?
          email_t = { "Read E-mails": 0, "Sent E-mails": 0 }
        else
          # TODO: figure out why some email_t are not nil but email_t.inbound or email_t.outbound are nil (Issue #692)
          email_t = { 
            "Read E-mails": email_t.inbound.nil? ? 0 : (email_t.inbound / User::WORDS_PER_SEC[:Read]).round,
            "Sent E-mails": email_t.outbound.nil? ? 0 : (email_t.outbound / User::WORDS_PER_SEC[:Write]).round
          }
        end
        meeting_t = meeting_time.find { |mt| mt.email == user.email }
        meeting_t = meeting_t.nil? ? { Meetings: 0 } : { Meetings: meeting_t.total }
        time_hash = meeting_t.merge(email_t)
        Hashie::Mash.new({ id: user.id, name: get_full_name(user), y: time_hash, total: time_hash.values.sum })
      end
      @categories = ["Meetings", "Read E-mails", "Sent E-mails"]
    when TEAM_DASHBOARD_METRIC[:opportunities]
      accounts_managed = users.includes(:projects_owner_of).group('users.id').order('count_projects_all DESC').count('projects.*')
      @data = accounts_managed.map do |uid, num_accounts|
        user = users.find { |usr| usr.id == uid }
        Hashie::Mash.new({ id: user.id, name: get_full_name(user), y: num_accounts })
      end
    when TEAM_DASHBOARD_METRIC[:new_alerts_and_tasks_last14d]
      new_tasks = users.select("users.*, COUNT(DISTINCT notifications.id) AS task_count").joins("LEFT JOIN notifications ON notifications.assign_to = users.id AND EXTRACT(EPOCH FROM notifications.created_at) >= #{14.days.ago.midnight.to_i}").group('users.id').order("task_count DESC")
      @data = new_tasks.map do |u|
        Hashie::Mash.new({ id: u.id, name: get_full_name(u), y: u.task_count })
      end
    when TEAM_DASHBOARD_METRIC[:closed_alerts_and_tasks_last14d]
      closed_tasks = users.select("users.*, COUNT(DISTINCT notifications.id) AS task_count").joins("LEFT JOIN notifications ON notifications.assign_to = users.id AND notifications.is_complete IS TRUE AND EXTRACT(EPOCH FROM notifications.complete_date) >= #{14.days.ago.midnight.to_i}").group('users.id').order("task_count DESC")
      @data = closed_tasks.map do |u|
        Hashie::Mash.new({ id: u.id, name: get_full_name(u), y: u.task_count })
      end
    when TEAM_DASHBOARD_METRIC[:open_alerts_and_tasks]
      open_tasks = users.select("users.*, COUNT(DISTINCT notifications.id) AS task_count").joins("LEFT JOIN notifications ON notifications.assign_to = users.id AND notifications.is_complete IS FALSE").group('users.id').order("task_count DESC")
      @data = open_tasks.map do |u|
        Hashie::Mash.new({ id: u.id, name: get_full_name(u), y: u.task_count })
      end
    else # Invalid
      @data = []
    end
    
    if @categories
      @data.sort!{ |d1, d2| (d1.total == d2.total) ? d1.name.upcase <=> d2.name.upcase : d2.total <=> d1.total } # sort using tiebreaker: user name, case-insensitive in alphabetical order
    else  # sort by y instead
      @data.sort!{ |d1, d2| (d1.y != d2.y) ? d2.y <=> d1.y : d1.name.upcase <=> d2.name.upcase }
    end

    # puts "**************** @data (#{@data.present? ? @data.length : 0}): #{@data} \t\t ****** @categories (#{@categories.present? ? @categories.length : 0}):  #{@categories}"
    @data = @data.take(25)  # TODO: real left chart pagination
  end

  # for loading User details (right panel) on Team Dashboard
  def td_user_data
    @user = User.where(organization_id: current_user.organization_id).find(params[:id])
    @error = "Oops, something went wrong. Try again." and return if @user.blank?

    @open_alerts = @user.notifications.open.count  #tasks and alerts
    @accounts_managed = @user.projects_owner_of.count
    @sum_expected_revenue = @user.projects_owner_of.sum(:expected_revenue)

    @activities_by_category_date = @user.daily_activities_by_category.group_by { |a| a.category }

    # compute Tasks Trend Data for this user on the fly, this may be done better with a materialized view in the future
    day_range = 14
    @tasks_trend_data = Hashie::Mash.new({total_open: Array.new(day_range + 1, 0), new_open: Array.new(day_range + 1, 0), new_closed: Array.new(day_range + 1, 0)})
    tasks = @user.notifications
    tasks_by_open_date = tasks.group("date(created_at AT TIME ZONE 'UTC' AT TIME ZONE '#{current_user.time_zone}')").count
    tasks_by_complete_date = tasks.group("date(complete_date AT TIME ZONE 'UTC' AT TIME ZONE '#{current_user.time_zone}')").count
    # count all new tasks on new_open and total_open trend lines
    tasks_by_open_date.each do |date, opened_tasks|
      date_index = date.mjd - day_range.days.ago.to_date.mjd
      @tasks_trend_data.new_open[date_index] += opened_tasks if date_index >= 0
      @tasks_trend_data.total_open.map!.with_index do |num_tasks, i|
        date_index <= i ? num_tasks + opened_tasks : num_tasks
      end
    end
    # count all completed tasks on new_closed and total_open trend lines
    tasks_by_complete_date.each do |date, completed_tasks|
      next if date.nil?
      date_index = date.mjd - day_range.days.ago.to_date.mjd
      @tasks_trend_data.new_closed[date_index] += completed_tasks if date_index >= 0
      @tasks_trend_data.total_open.map!.with_index do |num_tasks, i|
        date_index <= i ? num_tasks - completed_tasks : num_tasks
      end
    end

    # compute Interaction Time per Account for this user on the fly
    meeting_time = @user.meeting_time_by_project
    email_time = @user.email_time_by_project
    @interaction_time_per_account = []
    meeting_time.each do |p|
      @interaction_time_per_account << Hashie::Mash.new(name: p.name, id: p.id, meeting_time: p.total_meeting_hours, sent_time: 0, read_time: 0, total: p.total_meeting_hours)
    end
    email_time.each do |p|
      i_t = @interaction_time_per_account.find { |it| it.id == p.id }
      if i_t.nil?
        @interaction_time_per_account << Hashie::Mash.new(name: p.name, id: p.id, meeting_time: 0, sent_time: p.outbound, read_time: p.inbound, total: p.outbound + p.inbound)
      else
        i_t.sent_time = p.outbound
        i_t.read_time = p.inbound
        i_t.total += p.outbound + p.inbound
      end
    end
    @interaction_time_per_account.sort_by! { |it| it.total }.reverse!

    # take the top 10 interaction time per account, currently allotted space only fits about 10 categories on xAxis before labels are cut off
    @interaction_time_per_account = @interaction_time_per_account.take(10)

    render layout: false
  end

  # for loading metrics data (left panel) on Accounts Opportunities Dashboard
  def ad_sort_data
    @metric = params[:sort]
    @metric_tick_interval = getTickIntervalForMetric(@metric)

    projects = Project.visible_to(current_user.organization_id, current_user.id)
    projects = projects.where(category: params[:category]) if params[:category].present?
    projects = projects.joins(:account).where(accounts: { category: params[:account] }) if params[:account].present?

    # Incrementally apply any filters
    if params[:owner].present?
      if params["owner"] == "none"
        projects = projects.where(owner_id: nil)
      elsif @owners.any? { |o| o.id == params[:owner] }  #check for a valid user_id before using it
        projects = projects.where(owner_id: params[:owner]);
      end
    end 

    @data = [] and return if projects.blank?  #quit early if all projects are filtered out

    case @metric
    when ACCOUNT_DASHBOARD_METRIC[:activities_last14d]
      project_engagement = Project.count_activities_by_category(projects.pluck(:id), current_user.organization.domain, current_user.time_zone).group_by { |p| p.id }
      @data = [] and @categories = [] and return if project_engagement.blank?
      @data = project_engagement.map do |pid, activities|
        proj = projects.find { |p| p.id == pid }
        
        Hashie::Mash.new({ id: proj.id, name: proj.name, deal_size: proj.amount, close_date: proj.close_date, y: activities, total: activities.inject(0){|sum,a| sum += (a.num_activities.present? ? a.num_activities : 0)} }) if proj.present?  # else nil
      end

      @data.compact!

      @categories = @data.inject([]) do |memo, d|
        d.y.each {|a| memo = memo | [a.category]}
        memo
      end  
    # when ACCOUNT_DASHBOARD_METRIC[:risk_score]
    #   risk_scores = projects.nil? ? [] : Project.new_risk_score(projects.ids, current_user.time_zone).sort_by { |pid, score| score }.reverse
    #   total_risk_scores = 0
    #   @data = risk_scores.map do |r|
    #     proj = projects.find { |p| p.id == r[0] }
    #     total_risk_scores += r[1]
    #     color = r[1] >= 80 ? 'highRisk' : r[1] >= 60 ? 'mediumRisk' : 'lowRisk'
    #     Hashie::Mash.new({ id: proj.id, name: proj.name, deal_size: proj.amount, close_date: proj.close_date, y: r[1], color: color })
    #   end
    #   @average = risk_scores.empty? ? 0 : (total_risk_scores.to_f/risk_scores.length).round(1)
    when ACCOUNT_DASHBOARD_METRIC[:days_inactive]
      last_sent_dates = projects.joins(:activities).where.not(activities: { category: [Activity::CATEGORY[:Note], Activity::CATEGORY[:Alert]] }).maximum("activities.last_sent_date").sort_by { |pid, date| date.nil? ? Time.current : date }
      @data = last_sent_dates.map do |d|
        proj = projects.find { |p| p.id == d[0] }
        y = d[1].nil? ? 0 : Date.current.mjd - d[1].in_time_zone.to_date.mjd
        Hashie::Mash.new({ id: proj.id, name: proj.name, deal_size: proj.amount, close_date: proj.close_date, y: y, color: 'default' })
      end
    # when ACCOUNT_DASHBOARD_METRIC[:negative_sentiment_activities_pct]
    #   project_engagement = Project.find_include_sum_activities(projects.pluck(:id))
    #   project_risks = projects.select("COUNT(DISTINCT notifications.id) AS risk_count").joins("LEFT JOIN notifications ON notifications.project_id = projects.id AND notifications.category = '#{Notification::CATEGORY[:Alert]}'").group("projects.id")
    #   @data = project_engagement.map do |e|
    #     risk = project_risks.find { |r| r.id == e.id }
    #     Hashie::Mash.new({ id: e.id, name: e.name, deal_size: e.amount, close_date: e.close_date, y: (risk.risk_count.to_f/e.num_activities*100).round(2), color: 'default'})
    #   end
    #   @data.sort_by! { |d| d.y }.reverse!
    when ACCOUNT_DASHBOARD_METRIC[:open_alerts]
      open_task_counts = Project.count_tasks_per_project(projects.pluck(:id))
      @data = open_task_counts.map do |r|
        Hashie::Mash.new({ id: r.id, name: r.name, deal_size: r.amount, close_date: r.close_date, y: r.open_risks, color: 'default'})
      end
    when ACCOUNT_DASHBOARD_METRIC[:overdue_tasks]
      overdue_tasks = projects.select("COUNT(DISTINCT notifications.id) AS task_count").joins("LEFT JOIN notifications ON notifications.project_id = projects.id AND notifications.is_complete IS FALSE AND EXTRACT(EPOCH FROM notifications.original_due_date) < #{Time.current.to_i}").group("projects.id").order("task_count DESC")
      @data = overdue_tasks.map do |t|
        Hashie::Mash.new({ id: t.id, name: t.name, deal_size: t.amount, close_date: t.close_date, y: t.task_count, color: 'default'})
      end
    when ACCOUNT_DASHBOARD_METRIC[:deal_size]
      deal_size = projects.select("projects.id, projects.name, COALESCE(projects.amount,0) AS deal_size").where("projects.amount > 0")
      @data = deal_size.map do |t|
        Hashie::Mash.new({ id: t.id, name: t.name, deal_size: t.amount, close_date: t.close_date, y: t.deal_size, color: 'default'})
      end
    when ACCOUNT_DASHBOARD_METRIC[:days_to_close]
      @data = projects.select{|p| p.close_date.present?}.map do |p| 
        days_to_close = (p.close_date - Date.today).to_i
        Hashie::Mash.new({ id: p.id, name: p.name, deal_size: p.amount, close_date: p.close_date, y: days_to_close, color: days_to_close < 0 ? 'negative': 'default'})
      end
    else # Invalid  
      @data = []
    end

    if @categories
      @data.sort!{ |d1, d2| (d1.total == d2.total) ? d1.name.upcase <=> d2.name.upcase : d2.total <=> d1.total } # sort using tiebreaker: opportunity name, case-insensitive in alphabetical order
    else  # sort by y instead
      @data.sort!{ |d1, d2| (d1.y != d2.y) ? d2.y <=> d1.y : d1.name.upcase <=> d2.name.upcase }  
    end

    # puts "**************** @data (#{@data.present? ? @data.length : 0}): #{@data} \t\t ****** @categories (#{@categories.present? ? @categories.length : 0}):  #{@categories}"
    @data = @data.take(25)  # TODO: real left chart pagination
  end

  # for loading "account" details (right panel) on Opportunities Dashboard ("account" in this case is an opportunities, internally known as a project)
  def ad_account_data
    @project = Project.visible_to(current_user.organization_id, current_user.id).find(params[:id])

    #@risk_score = @project.new_risk_score(current_user.time_zone)
    @open_tasks_count = @project.notifications.open.count
    @last_activity_date = @project.activities.where.not(category: [Activity::CATEGORY[:Note], Activity::CATEGORY[:Alert]]).maximum("activities.last_sent_date")
    #@risk_score_trend = @project.new_risk_score_trend(current_user.time_zone)

    # Engagement Volume Chart
    @activities_moving_avg = @project.activities_moving_average(current_user.time_zone)
    @activities_by_category_date = @project.daily_activities_last_x_days(current_user.time_zone).group_by { |a| a.category }

    #TODO: Query for usage_report finds all the read and write times from internal users
    #Metric for Interaction Time
    # Read and Sent times
    @in_outbound_report = User.total_team_usage_report([@project.account.id], current_user.organization.users.pluck(:email))
    #Meetings in Interaction Time
    @meeting_report = User.meeting_team_report([@project.account.id], current_user.organization.users.pluck(:email))

    # TODO: Modify query and method params for count_activities_by_user_flex to take project_ids instead of account_ids
    # Most Active Contributors & Activities By Team
    user_num_activities = User.count_activities_by_user_flex([@project.account.id], current_user.organization.domain)
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

  #### Private helper functions ####
  private

  def get_owners_in_org
    @owners = User.where(organization_id: current_user.organization_id).order('LOWER(first_name) ASC')
  end

  def getTickIntervalForMetric(metric)
    if [ACCOUNT_DASHBOARD_METRIC[:activities_last14d], ACCOUNT_DASHBOARD_METRIC[:open_alerts], ACCOUNT_DASHBOARD_METRIC[:overdue_tasks]].include? metric
      5
    elsif [TEAM_DASHBOARD_METRIC[:activities_last14d], TEAM_DASHBOARD_METRIC[:new_alerts_and_tasks_last14d], TEAM_DASHBOARD_METRIC[:closed_alerts_and_tasks_last14d], TEAM_DASHBOARD_METRIC[:open_alerts_and_tasks]].include? metric
      5
    else
      "null"
    end
  end
end
