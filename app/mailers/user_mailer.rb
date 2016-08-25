class UserMailer < ApplicationMailer
  add_template_helper(MailerHelper)

  def welcome_email(user, num_of_projects, url)
    @user = user
    @num_of_projects = num_of_projects
    @url = url

    track user: user # ahoy_email tracker
    track click: false # disable ahoy_email click tracker for links in email
    track open: false # disable ahoy_email open tracker
    mail(to: @user.email, subject: "Your Account Streams are ready at ContextSmith")
  end

  def daily_summary_email(user)
    @user = user
    d_tz = Time.current.yesterday.midnight.utc

    activity_from_yesterday = "activities.last_sent_date BETWEEN TIMESTAMP '#{d_tz}' AND TIMESTAMP '#{d_tz}' + INTERVAL '24 hours'"
    your_notifications = "((notifications.is_complete = false) OR (notifications.is_complete = true AND notifications.complete_date BETWEEN TIMESTAMP '#{d_tz}' AND TIMESTAMP '#{d_tz}' + INTERVAL '24 hours')) AND (notifications.assign_to = '#{user.id}')"

    sub = user.subscriptions

    if !sub.nil? and !sub.empty?
      updates_today = Project.visible_to(user.organization_id, user.id).following(user.id).includes(:activities, :account, :notifications).where(activity_from_yesterday + " OR " + your_notifications).group("activities.id, accounts.id, notifications.id")
      @updates_today = updates_today.map do |proj|
        # create a copy of each project to avoid deleting records when filtering relations
        temp = proj.dup
        # temp = Project.new     # another option
        # assign relations before id
        temp.activities = proj.activities.where(activity_from_yesterday).select { |a| a.is_visible_to(user) }
        temp.notifications = proj.notifications.where(your_notifications).order(:is_complete, :original_due_date)
        temp.account = proj.account
        # CAUTION: if id is assigned before the relations, assigned relation will be overwritten in actual record
        temp.id = proj.id
        temp
      end

      track user: user # ahoy_email tracker
      track click: false # disable ahoy_email click tracker for links in email
      track open: false # disable ahoy_email open tracker
      mail(to: user.email, subject: "Daily Summary for #{Time.current.yesterday.strftime('%A, %B %d')}")
    end
  end

  def weekly_summary_email(user)
    @user = user

    open_or_recently_closed = "notifications.is_complete = false OR notifications.complete_date BETWEEN CURRENT_TIMESTAMP - INTERVAL '1 week' and CURRENT_TIMESTAMP"
    
    @subs = user.subscriptions

    if !@subs.nil? and !@subs.empty?
      @projects_with_tasks = Project.visible_to(user.organization_id, user.id).following(user.id).includes(:account, notifications: :assign_to_user).where(open_or_recently_closed).group("notifications.id, accounts.id, users.id")
      @your_soon_tasks_count = @projects_with_tasks.map(&:notifications).flatten.select { |t| !t.is_complete && !t.original_due_date.nil? && !t.assign_to.nil? && t.original_due_date > Time.current && t.original_due_date < 7.days.from_now && t.assign_to == user.id }.length

      track user: user # ahoy_email tracker
      track click: false # disable ahoy_email click tracker for links in email
      track open: false # disable ahoy_email open tracker
      mail(to: user.email, subject: "Weekly Summary for #{1.week.ago.strftime('%A, %B %d')} - #{Time.current.strftime('%A, %B %d')}")
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
    track click: false # disable ahoy_email click tracker for links in email
    track open: false # disable ahoy_email open tracker
    mail(to: @user.email, subject: "#{invited_by} invites you to join ContextSmith")
  end

  def task_assigned_notification_email(task, assigner)
    @user = task.assign_to_user
    @project = task.project
    @assigner = assigner
    @task = task

    track user: @user # ahoy_email tracker
    track click: false # disable ahoy_email click tracker for links in email
    track open: false # disable ahoy_email open tracker
    mail(to: @user.email, subject: "#{get_full_name(assigner)} assigned a task to you: #{@task.name}")
  end
end
