class UserMailer < ApplicationMailer
  add_template_helper(MailerHelper)

  def welcome_email(user)
    @user = user

    puts "Emailing welcome email to #{user.email}"
    mail(to: @user.email, subject: "Welcome to ContextSmith", from: "will@contextsmith.com")
  end

  def weekly_tracking_summary(user)
    @user = user
    email_recipients_domain = []
    email_recipients = []
    email_recipients_last_week = []

    # last 60 days of emails sent + their history and emails opened + their history
    # sql_where = "tracking_requests.tracking_id in (
    #                select tracking_id from tracking_requests where user_id='#{user.id}' and sent_at > NOW() - interval '7' day
    #                 UNION
    #                select e.tracking_id from tracking_events e join tracking_requests r on e.tracking_id=r.tracking_id where date > NOW() - interval '7' day and r.user_id='#{user.id}')"

    # @trackings = TrackingRequest.includes(:tracking_events)
    #                  .where(sql_where)
    #                  .order('tracking_events.date DESC NULLS LAST').order('sent_at DESC');

    @unopened = TrackingRequest.find_by_sql("SELECT user_id,subject,sent_at,recipients, email_id, count(e.id) as cnt 
                  FROM tracking_requests r left outer join tracking_events e on e.tracking_id = r.tracking_id 
                  WHERE r.user_id='#{user.id}' AND r.sent_at > NOW() - interval '7' day group by 1,2,3,4,5 having count(e.id) = 0;")

    tracking_recipients = TrackingRequest.select("recipients").where("sent_at > NOW() - interval '7' day and user_id='#{user.id}'")
    tracking_recipients_last_week = TrackingRequest.select("recipients").where("sent_at >= NOW() - interval '14' day and sent_at < NOW() - interval '7' day and user_id='#{user.id}'")
    
    # Sorted email domain count - for bar chart
    tracking_recipients.each {|e| email_recipients_domain << e.recipients.flatten.to_s.tr('[]"', '').split("@").last}
    email_domain_counts = email_recipients_domain.group_by{|e| e}.map{|k, v| [k, v.length]}.to_h
    @sorted_email_domain_counts = email_domain_counts.sort_by {|_key, value| -value} #sort by reverse (therefore negative "value")

    # Unique recipient count - for summary
    tracking_recipients.each {|e| email_recipients << e.recipients.flatten.to_s.tr('[]"', '')}
    tracking_recipients_last_week.each {|e| email_recipients_last_week << e.recipients.flatten.to_s.tr('[]"', '')}
    @email_recipients_count = email_recipients.uniq.count
    puts "Email recipients count: " + @email_recipients_count.to_s
    email_recipients_count_last_week = email_recipients_last_week.uniq.count
    puts "Email recipients count last week: " + email_recipients_count_last_week.to_s
    @email_recipients_change = get_percent_change(email_recipients_count_last_week, @email_recipients_count)
    puts "Email recipients change: " + @email_recipients_change.to_s + "%"

    @emails_sent = TrackingRequest.where("sent_at > NOW() - interval '7' day and user_id='#{user.id}'").count
    puts "Emails sent: " + @emails_sent.to_s
    emails_sent_last_week = TrackingRequest.where("sent_at >= NOW() - interval '14' day and sent_at < NOW() - interval '7' day and user_id='#{user.id}'").count
    puts "Emails sent last week: " + emails_sent_last_week.to_s
    @emails_sent_change = get_percent_change(emails_sent_last_week, @emails_sent)
    puts "Emails sent change: " + @emails_sent_change.to_s + "%"

    emails_opened = TrackingEvent.select("distinct tracking_id").where("tracking_id in (select tracking_id from tracking_requests where user_id='#{user.id}' AND sent_at > NOW() - interval '7' day)").count
    puts "Emails opened: " + emails_opened.to_s
    emails_opened_last_week = TrackingEvent.select("distinct tracking_id").where("tracking_id in (select tracking_id from tracking_requests where user_id='#{user.id}' AND sent_at >= NOW() - interval '14' day and sent_at < NOW() - interval '7' day)").count
    puts "Emails opened last week: " + emails_opened_last_week.to_s
    @emails_open_percent = get_percent(emails_opened, @emails_sent)
    puts "Emails open percent: " + @emails_open_percent.to_s + "%"
    emails_open_percent_last_week = get_percent(emails_opened_last_week, emails_sent_last_week)
    puts "Emails open percent last week: " + emails_open_percent_last_week.to_s + "%"
    @emails_open_percent_change = get_percent_change(emails_open_percent_last_week, @emails_open_percent)
    puts "Emails open percent change: " + @emails_open_percent_change.to_s + "%"

    puts "Emailing weekly tracking summary to #{user.email}"
    mail(to: user.email, subject: "Weekly email tracking summary: #{1.week.ago.strftime('%b %d')} - #{Time.current.yesterday.strftime('%b %d')}")
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
      @colleagues = registered_users + " and #{@user.organization.users.registered.size - 3} teammates are already using ContextSmith to share and stay on top of your customers."
    elsif @user.organization.users.registered.size == 1
      @colleagues = "Join #{invited_by.split(' ').first} is using ContextSmith to share and stay on top of your customers."
    else
      registered_users = @user.organization.users.registered.map(&:first_name).join(' and ')
      @colleagues = registered_users + " are already using ContextSmith to share and stay on top of your customers."
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

  private

  def get_percent(numerator, denominator)
    if denominator == 0 and numerator > 0
      return 100
    elsif denominator == 0 and numerator == 0
      return 0
    else
      ((numerator.to_f / denominator.to_f) * 100.0).round(0)
    end
  end

  def get_percent_change(v1, v2)
    #((v2 - v1) / v1)*100 = your percent change
    if v1 == 0 and v2 > 0
      return 100
    elsif v2 == 0 and v1 == 0
      return 0
    else
      return (((v2 - v1).to_f / v1.to_f) * 100.0).round(0)
    end
  end
end
