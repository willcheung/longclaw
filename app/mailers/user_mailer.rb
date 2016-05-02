class UserMailer < ApplicationMailer
  add_template_helper(MailerHelper)

  def welcome_email(user, num_of_projects, url)
    @user = user
    @num_of_projects = num_of_projects
    @url = url

    track user: user # ahoy_email tracker
    mail(to: @user.email, subject: "Your project streams are ready at ContextSmith")
  end

  def daily_summary_email(user)
    @user = user
    d_tz = Time.current.yesterday.strftime('%F')

    where = " between to_timestamp(#{Time.zone.parse(d_tz).utc.to_i}) and (to_timestamp(#{Time.zone.parse(d_tz).utc.to_i}) + interval '24 hours')"
    
    sub = user.subscriptions

    if !sub.nil? and !sub.empty?
      activities_today = Project.visible_to(user.organization_id, user.id).following(user.id).eager_load([:activities, :account]).where("activities.last_sent_date" + where).group("activities.id, accounts.id")
      @projects_with_activities_today = activities_today.group_by{|e| e.activities.select {|a| a.is_visible_to(user) }}

      # pinned_activities_today = Project.visible_to(user.organization_id, user.id).following(user.id).eager_load([:activities]).where("activities.is_pinned = true and activities.pinned_at" + where).group("activities.id")
      # @pinned_activities_today = pinned_activities_today.collect { |x| x.activities.select {|a| a.is_visible_to(current_user) }}.flatten

      track user: user # ahoy_email tracker
      mail(to: user.email, subject: "Daily Summary for #{Time.current.yesterday.strftime('%A, %B %d')}")
    end
  end

  def weekly_summary_email(user)
    @user = user

    open_or_recently_closed = "notifications.is_complete = false OR notifications.complete_date BETWEEN CURRENT_TIMESTAMP - INTERVAL '1 week' and CURRENT_TIMESTAMP"
    
    @subs = user.subscriptions

    if !@subs.nil? and !@subs.empty?
      @projects_with_tasks = Project.visible_to(user.organization_id, user.id).following(user.id).includes(:account, notifications: :assign_to_user).where(open_or_recently_closed).group("notifications.id, accounts.id, users.id")
      @your_soon_tasks_count = @projects_with_tasks.map(&:notifications).flatten.select { |t| !t.is_complete && t.original_due_date > Time.current && t.original_due_date < 7.days.from_now && t.assign_to == user.id }.length
      # @tasks = @projects_with_tasks.map(&:notifications).flatten
      # @open_tasks = @tasks.reject { |t| t.is_complete }
      # @closed_tasks_count = @tasks.length - @open_tasks.length
      # @assigned_tasks_count = @open_tasks.select { |t| t.assign_to == user.id }.length
      # @overdue_tasks = @open_tasks.select { |t| t.original_due_date < Time.current }
      # @recent_tasks_count = @open_tasks.select { |t| t.created_at > 7.days.ago }.length

      track user: user # ahoy_email tracker
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
    mail(to: @user.email, subject: "#{invited_by} invites you to join ContextSmith")
  end

end
