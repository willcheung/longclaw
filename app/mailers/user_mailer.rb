class UserMailer < ApplicationMailer
  add_template_helper(MailerHelper)

  def welcome_email(user, num_of_projects, url)
    @user = user
    @num_of_projects = num_of_projects
    @url = url

    track user: user # ahoy_email tracker
    mail(to: @user.email, subject: "Your Account Streams are ready at ContextSmith")
  end

  def daily_summary_email(user)
    @user = user
    sub = user.subscriptions.daily

    unless sub.blank?
      puts "Checking daily subscription for #{user.email}"
      @current_user_timezone = user.time_zone
      @updates_today = Project.visible_to(user.organization_id, user.id).following_daily(user.id).preload(:conversations_for_daily_email, :other_activities_for_daily_email, :notifications_for_daily_email)
      @updates_today = @updates_today.map do |proj|
        # create a copy of each project to avoid deleting records when filtering relations
        temp = proj.dup
        # temp = Project.new     # another option
        # assign relations before id
        temp.activities = (proj.conversations_for_daily_email.visible_to(user.email) + proj.other_activities_for_daily_email.visible_to(user.email)).sort  {|a,b| b.last_sent_date <=> a.last_sent_date }
        temp.notifications = proj.notifications_for_daily_email
        temp.account = proj.account
        # CAUTION: if id is assigned before the relations, assigned relation will be overwritten in actual record
        temp.id = proj.id
        temp
      end
      @updates_today.reject! { |proj| proj.activities.blank? && proj.notifications.blank? }
      @risk_scores = Project.new_risk_score(@updates_today.map(&:id), user.time_zone) unless @updates_today.blank?

      track user: user # ahoy_email tracker
      puts "Emailing daily summary to #{user.email}"
      mail(to: user.email, subject: "Daily Summary for #{Time.current.yesterday.strftime('%A, %B %d')}")
    end
  end

  def weekly_summary_email(user)
    open_or_recently_closed = "notifications.is_complete = false OR notifications.complete_date BETWEEN CURRENT_TIMESTAMP - INTERVAL '1 week' and CURRENT_TIMESTAMP"
    
    @subs = user.subscriptions.weekly

    if !@subs.nil? and !@subs.empty?
      puts "Checking weekly subscription for #{user.email}"
      @current_user_timezone = user.time_zone
      @projects = Project.visible_to(user.organization_id, user.id).following_weekly(user.id).includes(:account, notifications: :assign_to_user).where(open_or_recently_closed).group("notifications.id, accounts.id, users.id")
      # @your_soon_tasks_count = @projects_with_tasks.map(&:notifications).flatten.select { |t| !t.is_complete && !t.original_due_date.nil? && !t.assign_to.nil? && t.original_due_date > Time.current && t.original_due_date < 7.days.from_now && t.assign_to == user.id }.length

      track user: user # ahoy_email tracker
      puts "Emailing weekly summary to #{user.email}"
      mail(to: user.email, subject: "Weekly Summary for #{1.week.ago.strftime('%A, %B %d')} - #{Time.current.yesterday.strftime('%A, %B %d')}")
    end
  end

  def user_invitation_email(user, invited_by, url)
    @user = user
    @invited_by = invited_by
    @url = url

    if @user.organization.users.registered.size > 3
      registered_users = @user.organization.users.registered.map(&:first_name)[0..2].join(', ')
      @colleagues = registered_users + " and #{@user.organization.users.registered.size - 3} teammates are already using ContextSmith to track the pulse of your customers."
    elsif @user.organization.users.registered.size == 1
      @colleagues = "Join #{invited_by.split(' ').first} and team to track the pulse of your customers."
    else
      registered_users = @user.organization.users.registered.map(&:first_name).join(' and ')
      @colleagues = registered_users + " are already using ContextSmith to track the pulse of your customers."
    end

    track user: user # ahoy_email tracker
    mail(to: @user.email, subject: "#{invited_by} invites you to join ContextSmith")
  end

  def task_assigned_notification_email(task, assigner)
    @user = task.assign_to_user
    @project = task.project
    @assigner = assigner
    @task = task

    track user: @user # ahoy_email tracker
    mail(to: @user.email, subject: "#{get_full_name(assigner)} assigned a task to you: #{@task.name}")
  end
end
