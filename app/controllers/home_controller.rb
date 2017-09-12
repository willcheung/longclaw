class HomeController < ApplicationController
  layout 'empty', only: 'access_denied'
  before_action :check_user_onboarding, only: :index
  before_action :get_current_org_users, only: :index

  def index
    @MEMBERS_LIST_LIMIT = 8 # Max number of Opportunity members to show in mouse-over tooltip

    # Load all projects/opportunities visible to user, belongs to user, and to which user is subscribed
    visible_projects = Project.visible_to(current_user.organization_id, current_user.id)
    @current_user_projects = visible_projects.owner_of(current_user.id).select("projects.*, false AS daily, false AS weekly")
    subscribed_projects = visible_projects.select("project_subscribers.daily, project_subscribers.weekly").joins(:subscribers).where(project_subscribers: {user_id: current_user.id}).group("project_subscribers.daily, project_subscribers.weekly")

    # Load data for the 3 dashboards at the top of page
    unless @current_user_projects.blank?
      project_engagement_7d = Project.count_activities_by_category(@current_user_projects.pluck(:id), current_user.organization.domain, [current_user.email], 7.days.ago.midnight.utc, Time.current.end_of_day.utc).group_by { |p| p.id }
      if project_engagement_7d.blank?
        @data_left = [] and @categories = []
      else
        @data_left = project_engagement_7d.map do |pid, activities|
          proj = @current_user_projects.find { |p| p.id == pid }
          Hashie::Mash.new({ id: proj.id, name: proj.name, deal_size: proj.amount, close_date: proj.close_date, y: activities, total: activities.inject(0){|sum,a| sum += (a.num_activities.present? ? a.num_activities : 0)} }) if proj.present?  # else nil
        end
      end
      @data_left.compact!
      @data_left.sort!{ |d1, d2| (d1.total == d2.total) ? d1.name.upcase <=> d2.name.upcase : d2.total <=> d1.total } # sort using tiebreaker: opportunity name, case-insensitive in alphabetical order

      @data_center = @data_left.sort{ |d1, d2| (d1.total == d2.total) ? d1.name.upcase <=> d2.name.upcase : d1.total <=> d2.total } # sort using tiebreaker: opportunity name, case-insensitive in alphabetical order

      open_task_counts = Project.count_tasks_per_project(@current_user_projects.pluck(:id))
      @data_right = open_task_counts.map do |r|
        Hashie::Mash.new({ id: r.id, name: r.name, deal_size: r.amount, close_date: r.close_date, y: r.open_risks, color: 'default'})
      end
      @data_right.sort!{ |d1, d2| (d1.y == d2.y) ? d1.name.upcase <=> d2.name.upcase : d2.y <=> d1.y } # sort using tiebreaker: opportunity name, case-insensitive in alphabetical order

      @categories = @data_left.inject([]) do |memo, d|
        d.y.each {|a| memo = memo | [a.category]}
        memo
      end  # get only categories that have data

      # puts "\t******************* @categories: #{@categories}"
      # puts "\t<<<<<<<<<<<<<<<<<<< @data_left:"
      # @data_left.each do |d|
      #   puts "d.name=#{d.name} d.total=#{d.total}"
      # end
      # puts "\t******************* @data_center:"
      # @data_center.each do |d|
      #   puts "d.name=#{d.name} d.total=#{d.total}"
      # end
      # puts "\t>>>>>>>>>>>>>>>>>>> @data_right:"
      # @data_right.each do |d|
      #   puts "d.name=#{d.name} d.y=#{d.y}"
      # end
    end

    # Load notifications for "My Alerts & Tasks"  
    unless @current_user_projects.blank?
      project_tasks = Notification.where(project_id: @current_user_projects.pluck(:id))
      @open_total_tasks = project_tasks.open.where("assign_to='#{current_user.id}'").sort_by{|t| t.original_due_date.blank? ? Time.at(0) : t.original_due_date }.reverse
      # Need these to show project name and user name instead of pid and uid
      @projects_reverse = @current_user_projects.map { |p| [p.id, p.name] }.to_h
    end

    # Load project data for "My Opportunities"
    @projects = (@current_user_projects + subscribed_projects).uniq(&:id).sort_by{|p| p.name.upcase} # projects/opportunities user owns or to which user is subscribed
    unless @projects.empty?
      project_ids_a = @projects.map(&:id)

      @sparkline = Project.count_activities_by_day_sparkline(project_ids_a, current_user.time_zone)
      @risk_scores = Project.new_risk_score(project_ids_a, current_user.time_zone)
      @open_risk_count = Project.open_risk_count(project_ids_a)
      @days_to_close = Project.days_to_close(project_ids_a)
      @project_days_inactive = visible_projects.joins(:activities).where.not(activities: { category: [Activity::CATEGORY[:Note], Activity::CATEGORY[:Alert]] }).where('activities.last_sent_date <= ?', Time.current).maximum("activities.last_sent_date") # get last_sent_date
      @project_days_inactive.each { |pid, last_sent_date| @project_days_inactive[pid] = Time.current.to_date.mjd - last_sent_date.in_time_zone.to_date.mjd } # convert last_sent_date to days inactive
      @next_meetings = Activity.meetings.next_week.select("project_id, min(last_sent_date) as next_meeting").where(project_id: project_ids_a).group("project_id")
      @next_meetings = Hash[@next_meetings.map { |p| [p.project_id, p.next_meeting] }]

      #@rag_status = Project.current_rag_score(project_ids_a)
    end

    # Unused metrics
    #@open_tasks_not_overdue = project_tasks.open.where("(original_due_date::date > ? or original_due_date is NULL) and category != '#{Notification::CATEGORY[:Alert]}'", Date.today)
    #@open_risks = project_tasks.open.alerts
    #@overdue_tasks = project_tasks.open.where("original_due_date::date <= ?", Date.today).where("assign_to='#{current_user.id}'")

    #p params
  end

  def daily_summary
    d_tz =  params[:date] || Time.current.strftime('%F')
    @date_with_timezone = Date.parse(d_tz)
    date_filter_offset = Time.current.seconds_since_midnight

    if Date.current <= @date_with_timezone
      where = " between (current_timestamp - interval '#{date_filter_offset} seconds') and current_timestamp"
    else
      where = " between to_timestamp(#{Time.zone.parse(d_tz).utc.to_i}) and (to_timestamp(#{Time.zone.parse(d_tz).utc.to_i}) + interval '24 hours')"
    end

    @sub = current_user.subscriptions.includes(:project)

    if !@sub.nil? and !@sub.empty?
      activities_today = Project.visible_to(current_user.organization_id, current_user.id).following_daily(current_user.id).eager_load([:activities, :account]).where("activities.last_sent_date" + where).group("activities.id, accounts.id")
      @projects_with_activities_today = activities_today.group_by{|e| e.activities.select {|a| a.is_visible_to(current_user) }}

      pinned_activities_today = Project.visible_to(current_user.organization_id, current_user.id).eager_load([:activities]).where("activities.is_pinned = true and activities.pinned_at" + where).group("activities.id")
      @pinned_activities_today = pinned_activities_today.collect { |x| x.activities.select {|a| a.is_visible_to(current_user) }}.flatten
    end
  end

  def access_denied
    # @extension_downloaded = true
    @extension_downloaded = request.user_agent.downcase.match(/chrome/) && cookies[:chromeNotificationBar] == 'false'
    # in case a Basic user signs up through main page, force sign out here so that they will sign in through extension and trigger onboarding
    if current_user.present? && current_user.onboarding_step == Utils::ONBOARDING[:fill_in_info]
      sign_out current_user
    end
  end

  private

  def check_user_onboarding
    if current_user.onboarding_step == Utils::ONBOARDING[:confirm_projects] and !current_user.cluster_create_date.nil?
      redirect_to onboarding_confirm_projects_path
    elsif current_user.onboarding_step == Utils::ONBOARDING[:confirm_projects] and current_user.cluster_create_date.nil?
      redirect_to onboarding_creating_clusters_path
    end
  end

end
