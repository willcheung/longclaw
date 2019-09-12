class UserMailer < ApplicationMailer
  add_template_helper(MailerHelper)

  def welcome_email(user)
    @user = user

    mail(to: @user.email, subject: "Welcome to ContextSmith", from: "will@contextsmith.com")
  end

  def daily_summary_email(user)
    return unless user.pro?
    Time.use_zone(user.time_zone) do
      @user = user
      @subs = user.valid_streams_subscriptions.daily
      @upcoming_meetings = user.upcoming_meetings  # backend call-back
      @project_days_inactive = Project.joins(:activities).where(id: @upcoming_meetings.map(&:project_id)).where.not(activities: { category: [Activity::CATEGORY[:Note], Activity::CATEGORY[:Alert], Activity::CATEGORY[:NextSteps]] }).where('activities.last_sent_date <= ?', Time.current).group("projects.id").maximum("activities.last_sent_date") # get last_sent_date

      puts "Checking daily subscription for #{user.email}"
      # Currently, will not send a daily summary e-mail unless user is subscribed to at least one project/opportunity.  TODO: Create a setting for subscribing to daily e-mail for calendar events.
      unless @subs.blank? #&& @upcoming_meetings.blank?
        @updates_today = Project.visible_to(user.organization_id, user.id).following_daily(user.id).preload(:conversations_for_daily_email, :other_activities_for_daily_email, :notifications_for_daily_email, :account_with_contacts_for_daily_email)
        @updates_today = @updates_today.map do |proj|
          # create a copy of each project to avoid deleting records when filtering relations
          temp = proj.dup
          # temp = Project.new     # another option
          # assign relations before id
          temp.activities = (proj.conversations_for_daily_email.visible_to(user.email) + proj.other_activities_for_daily_email.visible_to(user.email)).sort_by {|a| a.last_sent_date }.reverse
          temp.notifications = proj.notifications_for_daily_email
          temp.contacts = proj.account_with_contacts_for_daily_email.blank? ? [] : proj.account_with_contacts_for_daily_email.contacts
          # CAUTION: if id is assigned before the relations, assigned relation will be overwritten in actual record
          temp.id = proj.id
          temp
        end

        @updates_today = @updates_today.reject { |proj| proj.activities.blank? && proj.notifications.blank? && proj.contacts.blank? }.sort_by { |proj| proj.activities.size + proj.notifications.size + proj.contacts.size }.reverse

        track user: user # ahoy_email tracker
        puts "Emailing daily summary to #{user.email}"
        mail(to: user.email, subject: "Daily Summary for #{Time.current.yesterday.strftime('%A, %B %d')}")
      end
    end
  end

  def weekly_summary_email(user)
    return unless user.pro?
    open_or_recently_closed = "notifications.id IS NULL OR notifications.is_complete = false OR notifications.complete_date BETWEEN CURRENT_TIMESTAMP - INTERVAL '1 week' and CURRENT_TIMESTAMP"
    
    @subs = user.valid_streams_subscriptions.weekly

    unless @subs.blank?
      puts "Checking weekly subscription for #{user.email}"
      @current_user_timezone = user.time_zone
      @projects = Project.visible_to(user.organization_id, user.id).following_weekly(user.id).includes(:account, notifications: :assign_to_user).where(open_or_recently_closed).group("notifications.id, accounts.id, users.id").order(:name)
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
      @colleagues = registered_users + " and #{@user.organization.users.registered.size - 3} teammates are already using ContextSmith to stay on top of accounts and sell smarter."
    elsif @user.organization.users.registered.size == 1
      @colleagues = "Join #{invited_by.split(' ').first} is using ContextSmith to stay on top of accounts and sell smarter."
    else
      registered_users = @user.organization.users.registered.map(&:first_name).join(' and ')
      @colleagues = registered_users + " are already using ContextSmith to stay on top of accounts and sell smarter."
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

  def update_cs_team(user)
    @user = user
    track user: @user # ahoy_email tracker
    mail(to:"support@contextsmith.com", subject: "#{get_full_name(@user)} signed up to ContextSmith")
  end

  def trial_ends_soon(user, plan, trial_ends)
    @user = user
    @plan = plan
    @trial_ends = trial_ends

    track user: @user # ahoy_email tracker
    mail(to: @user.email, subject: "Your trial of #{@plan} is ending in #{trial_ends}")
  end

  def subscription_cancelled(user)
    @user = user

    track user: @user # ahoy_email tracker
    mail(to: @user.email, subject: "#{@user.first_name}, your ContextSmith subscription has expired!")
  end
end
