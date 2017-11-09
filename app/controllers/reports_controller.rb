class ReportsController < ApplicationController
  before_action :get_owners_in_org, only: [:accounts_dashboard, :ad_sort_data]

  ACCOUNT_DASHBOARD_METRIC = { :activities_last14d => "Activities (Last 14d)", :days_inactive => "Days Inactive", :open_alerts_and_tasks => "Open Alerts & Tasks", :overdue_tasks => "Total Overdue Tasks", :deal_size => "Deal Size", :days_to_close => "Days to Close"} # Removed: :risk_score => "Risk Score"
  TEAM_DASHBOARD_METRIC = { :activities_last14d => "Activities (Last 14d)", :time_spent_last14d => "Time Spent (Last 14d)", :closed_won => "Closed Won", :win_rate => "Win Rate", :opportunities => "Opportunities", :closed_alerts_and_tasks_last14d => "Closed Alerts & Tasks (Last 14d)", :open_alerts_and_tasks => "Open Alerts & Tasks" } # Removed: :new_alerts_and_tasks_last_14d

  # "accounts_dashboard" is actually referring to opportunities, AKA projects
  def accounts_dashboard
    custom_lists = current_user.organization.get_custom_lists_with_options
    @account_types = !custom_lists.blank? ? custom_lists["Account Type"] : {}
    @opportunity_types = !custom_lists.blank? ? custom_lists["Opportunity Type"] : {}

    params[:sort] = ACCOUNT_DASHBOARD_METRIC[:activities_last14d]
    ad_sort_data
  end

  # for loading metrics data (left panel) on Accounts Opportunities Dashboard
  def ad_sort_data
    @metric = params[:sort]

    projects = Project.visible_to(current_user.organization_id, current_user.id)
    params[:close_date] = Project::CLOSE_DATE_RANGE[:ThisQuarter] if params[:close_date].blank?
    projects = projects.close_date_within(params[:close_date]) unless params[:close_date] == 'Any'
    users_emails = current_user.organization.users.pluck(:email)

    # Incrementally apply any filters
    if params[:owner].present?
      if params["owner"] == "none"
        projects = projects.where(owner_id: nil)
      elsif @owners.any? { |o| o.id == params[:owner] }  #check for a valid user_id before using it
        projects = projects.where(owner_id: params[:owner]);
      end
    end

    top_dash_projects = projects
    projects = projects.where(stage: params[:stage]) if params[:stage].present?

    @this_qtr_range = Project.get_close_date_range(Project::CLOSE_DATE_RANGE[:ThisQuarter])

    @data = [] and return if projects.blank?  #quit early if all projects are filtered out

    # Dashboard top charts
    set_top_dashboard_data(project_ids: top_dash_projects.pluck(:id))

    case @metric
    when ACCOUNT_DASHBOARD_METRIC[:activities_last14d]
      project_engagement = Project.count_activities_by_category(projects.pluck(:id), current_user.organization.domain, users_emails).group_by { |p| p.id }
      @data = [] and @categories = [] and return if project_engagement.blank?

      @data = project_engagement.map do |pid, activities|
        proj = Project.find pid
        Hashie::Mash.new({ id: proj.id, name: proj.name, deal_size: proj.amount, close_date: proj.close_date, y: activities, total: activities.inject(0){|sum,a| sum += (a.num_activities.present? ? a.num_activities : 0)} }) if proj.present?  # else nil
      end

      @data.compact!

      @categories = @data.inject([]) do |memo, d|
        d.y.each {|a| memo = memo | [a.category]}
        memo
      end  # get (and show in legend) only categories that have data
    when ACCOUNT_DASHBOARD_METRIC[:days_inactive]
      last_sent_dates = projects.order("days_inactive DESC").joins(:activities).where.not(activities: { category: [Activity::CATEGORY[:Note], Activity::CATEGORY[:Alert]] }).group("projects.id").select("date_part('day', CURRENT_TIMESTAMP AT TIME ZONE '#{current_user.time_zone}' - MAX(activities.last_sent_date AT TIME ZONE '#{current_user.time_zone}')) AS days_inactive")

      @data = last_sent_dates.map do |d|
        Hashie::Mash.new({ id: d.id, name: d.name, deal_size: d.amount, close_date: d.close_date, y: d.days_inactive, color: 'default' })
      end
    when ACCOUNT_DASHBOARD_METRIC[:open_alerts_and_tasks]
      open_task_counts = Project.count_tasks_per_project(projects.pluck(:id))
      @data = open_task_counts.map do |r|
        Hashie::Mash.new({ id: r.id, name: r.name, deal_size: r.amount, close_date: r.close_date, y: r.open_risks, color: 'default'})
      end
    when ACCOUNT_DASHBOARD_METRIC[:overdue_tasks]
      overdue_tasks = projects.select("COUNT(DISTINCT notifications.id) AS task_count").joins("LEFT JOIN notifications ON notifications.project_id = projects.id AND notifications.category != '#{Notification::CATEGORY[:Attachment]}' AND notifications.is_complete IS FALSE AND EXTRACT(EPOCH FROM notifications.original_due_date) < #{Time.current.to_i}").group("projects.id").order("task_count DESC")
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

    # puts "**************** @data (#{@data.present? ? @data.length : 0}): #{@data} \t\t ****** @categories(#{@categories.present? ? @categories.length : 0}):  #{@categories}"
    @data = @data.take(25)  # TODO: real left chart pagination
  end

  # for loading "account" details (right panel) on Opportunities Dashboard ("account" in this case is an opportunities, internally known as a project)
  def ad_account_data
    @project = Project.visible_to(current_user.organization_id, current_user.id).find(params[:id])

    #@risk_score = @project.new_risk_score(current_user.time_zone)
    @open_tasks_count = @project.notifications.open.count
    # @last_activity_date = @project.activities.where.not(category: [Activity::CATEGORY[:Note], Activity::CATEGORY[:Alert]]).maximum("activities.last_sent_date")
    #@risk_score_trend = @project.new_risk_score_trend(current_user.time_zone)

    # Alerts & Tasks
    @alerts_tasks = @project.notifications.order(:is_complete, :created_at).limit(8)
    # Next Meeting
    @next_meeting = @project.meetings.next_week.last

    # Engagement Volume Chart
    # @activities_moving_avg = @project.activities_moving_average(current_user.time_zone)
    @activities_by_category_date = @project.daily_activities_in_date_range(current_user.time_zone).group_by { |a| a.category }

    #TODO: Query for usage_report finds all the read and write times from internal users
    #Metric for Interaction Time
    @interaction_time_report = @project.interaction_time_by_user(current_user.organization.users)

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

  def team_dashboard
    users = current_user.organization.users
    @departments = users.pluck(:department).compact.uniq
    @titles = users.pluck(:title).compact.uniq

    params[:sort] = TEAM_DASHBOARD_METRIC[:win_rate]
    params[:metric] = TEAM_DASHBOARD_METRIC[:time_spent_last14d]
    td_sort_data
  end

  # for loading metrics data (left panel) on Team Dashboard
  def td_sort_data
    # NOTE: `sort` and `sort_by` are keywords for Hash, would have used these as keys for @dashboard_data but can't due to this conflict!
    @dashboard_data = Hashie::Mash.new(sorted_by: { type: params[:sort] }, metric: { type: params[:metric] })
    users = current_user.organization.users.registered.onboarded.non_alias

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

    @this_qtr_range = Project.get_close_date_range(Project::CLOSE_DATE_RANGE[:ThisQuarter])

    return if users.blank? # quit early if all users are filtered out

    projects = Project.visible_to(current_user.organization_id, current_user.id).is_confirmed
    params[:close_date] = Project::CLOSE_DATE_RANGE[:ThisQuarter] if params[:close_date].blank?
    projects = projects.close_date_within(params[:close_date]) unless params[:close_date] == 'Any'

    top_dash_projects = projects
    projects = projects.where(stage: params[:stage]) if params[:stage].present?

    return if projects.blank? # quit early if all projects are filtered out

    # Dashboard top charts
    if (params[:team].present? || params[:title].present?)
      set_top_dashboard_data(project_ids: top_dash_projects.pluck(:id), user_ids: users.pluck(:id)) # if any user filter is specified, then filter by users
    else
      set_top_dashboard_data(project_ids: top_dash_projects.pluck(:id)) # if no user filter is present, don't filter by users at all
    end

    @dashboard_data.sorted_by.data, @dashboard_data.sorted_by.categories = get_leaderboard_data(@dashboard_data.sorted_by.type, users, projects)
    @dashboard_data.metric.data, @dashboard_data.metric.categories = get_leaderboard_data(@dashboard_data.metric.type, users, projects, @dashboard_data.sorted_by.data)
  end

  # for loading User details (right panel) on Team Dashboard
  def td_user_data
    @user = User.where(organization_id: current_user.organization_id).find(params[:id])
    @error = "Oops, something went wrong. Try again." and return if @user.blank?

    @open_alerts_and_tasks = @user.notifications.open.count  #tasks and alerts
    @accounts_managed = @user.projects_owner_of.count
    # @sum_expected_revenue = @user.projects_owner_of.sum(:expected_revenue)
    @closed_won_this_qtr = Project.where(stage: 'Closed Won', close_date: Project.get_close_date_range(Project::CLOSE_DATE_RANGE[:ThisQuarter]), id: @user.projects_owner_of.ids).sum(:amount) # TODO: To take into account custom "Closed Won"/"Closed Lost" stages, use native is_closed and is_won flags

    @activities_by_category_date = @user.daily_activities_by_category(current_user.time_zone).group_by { |a| a.category }

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
    email_time = @user.email_time_by_project
    meeting_time = @user.meeting_time_by_project
    attachment_time = @user.sent_attachments_by_project
    @interaction_time_per_account = email_time.map do |p|
      Hashie::Mash.new(name: p.name, id: p.id, deal_size: p.amount, close_date: p.close_date, 'Meetings': 0, 'Attachments': 0, 'Sent E-mails': p.outbound, 'Read E-mails': p.inbound, total: p.inbound + p.outbound)
    end
    meeting_time.each do |p|
      i_t = @interaction_time_per_account.find { |it| it.id == p.id }
      if i_t.nil?
        @interaction_time_per_account << Hashie::Mash.new(name: p.name, id: p.id, deal_size: p.amount, close_date: p.close_date, 'Meetings': p.total_meeting_hours, 'Attachments': 0, 'Sent E-mails': 0, 'Read E-mails': 0, total: p.total_meeting_hours)
      else
        i_t.Meetings = p.total_meeting_hours
        i_t.total += p.total_meeting_hours
      end
    end
    attachment_time.each do |p|
      attachment_t = p.attachment_count * User::ATTACHMENT_TIME_SEC
      i_t = @interaction_time_per_account.find { |it| it.id == p.id }
      if i_t.nil?
        @interaction_time_per_account << Hashie::Mash.new(name: p.name, id: p.id, deal_size: p.amount, close_date: p.close_date, 'Meetings': 0, 'Attachments': attachment_t, 'Sent E-mails': 0, 'Read E-mails': 0, total: attachment_t)
      else
        i_t.Attachments = attachment_t
        i_t.total += attachment_t
      end
    end
    @interaction_time_per_account.sort_by! { |it| it.total.to_f }.reverse!
    # take the top 8 interaction time per account, currently allotted space only fits about 8 categories on xAxis before labels are cut off
    @interaction_time_per_account = @interaction_time_per_account.take(8)

    render layout: false
  end

  #### Private helper functions ####
  private

  def get_owners_in_org
    @owners = User.where(organization_id: current_user.organization_id).order('LOWER(first_name) ASC')
  end

  def get_leaderboard_data(metric, users, projects, ordered_by=nil)
    data = []
    categories = nil
    case metric
      when TEAM_DASHBOARD_METRIC[:activities_last14d]
        user_activities = User.count_all_activities_by_user(projects.ids, users.ids).group_by { |u| u.id }
        return [data, categories] if user_activities.blank?

        data = user_activities.map do |uid, activities|
          user = users.find { |usr| usr.id == uid }
          Hashie::Mash.new({ id: user.id, name: get_full_name(user), y: activities, total: activities.sum(&:num_activities) })
        end

        categories = data.inject([nil]) do |memo, p|
          memo | p.y.select {|a| a.num_activities > 0}.map(&:category)
        end  # get (and show in legend) only categories that have data
      when TEAM_DASHBOARD_METRIC[:time_spent_last14d]
        project_ids = projects.ids
        user_emails = users.pluck(:email)
        return [data, categories] if project_ids.blank? || user_emails.blank?

        email_time = User.team_usage_report(project_ids, user_emails)
        meeting_time = User.meeting_report(project_ids, user_emails)
        attachment_count = User.sent_attachments_count(project_ids, user_emails)
        data = users.map do |user|
          email_t = email_time.find { |et| et.email == user.email }
          if email_t.nil?
            email_t = { "Read E-mails": 0, "Sent E-mails": 0 }
          else
            # TODO: figure out why some email_t are not nil but email_t.inbound or email_t.outbound are nil (Issue #692)
            email_t = {
                "Read E-mails": (email_t.inbound / User::WORDS_PER_SEC[:Read]).round,
                "Sent E-mails": (email_t.outbound / User::WORDS_PER_SEC[:Write]).round
            }
          end
          meeting_t = meeting_time.find { |mt| mt.email == user.email }
          meeting_t = meeting_t.nil? ? { Meetings: 0 } : { Meetings: meeting_t.total }
          attachment_t = attachment_count.find { |at| at.email == user.email }
          attachment_t = attachment_t.nil? ? { Attachments: 0 } : { Attachments: attachment_t.attachment_count * User::ATTACHMENT_TIME_SEC }
          time_hash = email_t.merge(meeting_t).merge(attachment_t)
          # time_hash = [email_t, meeting_t, attachment_t].reduce(&:merge)
          Hashie::Mash.new({ id: user.id, name: get_full_name(user), y: time_hash, total: time_hash.values.sum })
        end
        categories = ["Meetings", "Attachments", "Read E-mails", "Sent E-mails"]
      when TEAM_DASHBOARD_METRIC[:opportunities]
        opportunities_owned = users.select("users.*, COUNT(DISTINCT projects.id) AS project_count")
                                  .joins("LEFT JOIN projects ON projects.owner_id = users.id AND projects.id IN ('#{projects.ids.join("','")}')")
                                  .group('users.id').order("project_count DESC")
        data = opportunities_owned.map do |u|
          Hashie::Mash.new({ id: u.id, name: get_full_name(u), y: u.project_count })
        end
      when TEAM_DASHBOARD_METRIC[:closed_won]
        closed_won = users.select("users.*, COALESCE(SUM(projects.amount), 0) AS closed_won_amount")
                        .joins("LEFT JOIN projects ON projects.owner_id = users.id AND projects.id IN ('#{projects.ids.join("','")}') AND projects.stage = 'Closed Won'") # TODO: use new projects.is_won IS TRUE instead of stage
                        .group('users.id').order("closed_won_amount DESC")
        data = closed_won.map do |u|
          Hashie::Mash.new({ id: u.id, name: get_full_name(u), y: u.closed_won_amount.round(2) })
        end
      when TEAM_DASHBOARD_METRIC[:win_rate]
        win_rates = users.select("users.*, COUNT(DISTINCT projects.id) AS project_count, COUNT(DISTINCT 
                CASE WHEN projects.stage = 'Closed Won' THEN projects.id 
                     ELSE null
                END ) AS win_count, COUNT(DISTINCT 
                CASE WHEN projects.stage = 'Closed Won' THEN projects.id 
                     ELSE null
                END)/GREATEST(COUNT(DISTINCT projects.id)::float, 1) * 100 AS win_rate")
                        .joins("LEFT JOIN projects ON projects.owner_id = users.id AND projects.id IN ('#{projects.ids.join("','")}')")
                        .group('users.id').order("win_rate DESC")  # TODO: use new projects.is_won IS TRUE instead of stage
        data = win_rates.map do |u|
          Hashie::Mash.new({ id: u.id, name: get_full_name(u), y: u.win_rate.round(2) })
        end
      # when TEAM_DASHBOARD_METRIC[:new_alerts_and_tasks_last14d]
      #   new_tasks = users.select("users.*, COUNT(DISTINCT notifications.id) AS task_count")
      #                   .joins("LEFT JOIN notifications ON notifications.assign_to = users.id AND notifications.category != '#{Notification::CATEGORY[:Attachment]}' AND notifications.project_id IN ('#{projects.ids.join("','")}') AND EXTRACT(EPOCH FROM notifications.created_at) >= #{14.days.ago.midnight.to_i}")
      #                   .group('users.id').order("task_count DESC")
      #   data = new_tasks.map do |u|
      #     Hashie::Mash.new({ id: u.id, name: get_full_name(u), y: u.task_count })
      #   end
      when TEAM_DASHBOARD_METRIC[:closed_alerts_and_tasks_last14d]
        closed_tasks = users.select("users.*, COUNT(DISTINCT notifications.id) AS task_count")
                           .joins("LEFT JOIN notifications ON notifications.assign_to = users.id AND notifications.category != '#{Notification::CATEGORY[:Attachment]}' AND notifications.project_id IN ('#{projects.ids.join("','")}') AND notifications.is_complete IS TRUE AND EXTRACT(EPOCH FROM notifications.complete_date) >= #{14.days.ago.midnight.to_i}")
                           .group('users.id').order("task_count DESC")
        data = closed_tasks.map do |u|
          Hashie::Mash.new({ id: u.id, name: get_full_name(u), y: u.task_count })
        end
      when TEAM_DASHBOARD_METRIC[:open_alerts_and_tasks]
        open_tasks = users.select("users.*, COUNT(DISTINCT notifications.id) AS task_count")
                         .joins("LEFT JOIN notifications ON notifications.assign_to = users.id AND notifications.category != '#{Notification::CATEGORY[:Attachment]}' AND notifications.project_id IN ('#{projects.ids.join("','")}') AND notifications.is_complete IS FALSE")
                         .group('users.id').order("task_count DESC")
        data = open_tasks.map do |u|
          Hashie::Mash.new({ id: u.id, name: get_full_name(u), y: u.task_count })
        end
      else # Invalid
        return [data, categories]
    end

    if ordered_by
    #   use order of the data already passed in
      data = data.index_by(&:id).values_at(*ordered_by.map(&:id))
    else
      if categories
        data.sort!{ |d1, d2| (d1.total == d2.total) ? d1.name.upcase <=> d2.name.upcase : d2.total <=> d1.total } # sort using tiebreaker: user name, case-insensitive in alphabetical order
      else  # sort by y instead
        data.sort!{ |d1, d2| (d1.y != d2.y) ? d2.y <=> d1.y : d1.name.upcase <=> d2.name.upcase }
      end
    end

    data = data.take(25)  # TODO: real left chart pagination
    # puts "**************** data(#{data.present? ? data.length : 0}) ************"
    # puts data
    # puts "************ categories(#{categories.present? ? categories.length : 0}) *************"
    # puts categories

    [data, categories]
  end

  # Sets the necessary data to be used in the top forecast category and stage reports.
  # Parameters:   project_ids (required) - list of CS opportunity id's to filter on.
  #               user_ids (optional) - list of CS user id's on which to filter project owners.
  def set_top_dashboard_data(project_ids: , user_ids: nil)
    if user_ids.present?
      forecast_chart_result = Project.select("COALESCE(projects.forecast, '-Undefined-')").where("projects.id IN (?) AND projects.owner_id IN (?)", project_ids, user_ids).group("COALESCE(projects.forecast, '-Undefined-')").sum("projects.amount").sort
      stage_chart_result = Project.select("COALESCE(projects.stage, '-Undefined-')").where("projects.id IN (?) AND projects.owner_id IN (?)", project_ids, user_ids).group("COALESCE(projects.stage, '-Undefined-')").sum("COALESCE(projects.amount,0)").sort
    else
      forecast_chart_result = Project.select("COALESCE(projects.forecast, '-Undefined-')").where("projects.id IN (?)", project_ids).group("COALESCE(projects.forecast, '-Undefined-')").sum("projects.amount").sort
      stage_chart_result = Project.select("COALESCE(projects.stage, '-Undefined-')").where("projects.id IN (?)", project_ids).group("COALESCE(projects.stage, '-Undefined-')").sum("projects.amount").sort
    end

    @lost_won_totals = stage_chart_result.select{|s,t| ['Closed Won','Closed Lost'].include? s} # TODO: To take into account custom "Closed Won"/"Closed Lost" stages, use is_closed and is_won flags

    stage_name_picklist = SalesforceOpportunity.get_sfdc_opp_stages(organization: current_user.organization)
    @forecast_chart_data = forecast_chart_result.map do |f, a|
      Hashie::Mash.new({ forecast_category_name: f, total_amount: a })
    end
    @stage_chart_data = stage_chart_result.sort do |x,y|
      stage_name_x = stage_name_picklist.find{|s| s.first == x.first}
      stage_name_x = stage_name_x.present? ? stage_name_x.second.to_s : '           '+x.first
      stage_name_y = stage_name_picklist.find{|s| s.first == y.first}
      stage_name_y = stage_name_y.present? ? stage_name_y.second.to_s : '           '+y.first
      stage_name_x <=> stage_name_y  # unmatched stage names are sorted to the left of everything
    end.map do |s, a|
      Hashie::Mash.new({ stage_name: s, total_amount: a })
    end
  end

end
