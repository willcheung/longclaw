class UserMailer < ApplicationMailer
  add_template_helper(MailerHelper)

  def welcome_email(user, num_of_projects, url)
    @user = user
    @num_of_projects = num_of_projects
    @url = url

    track user: user # ahoy_email tracker
    mail(to: @user.email, subject: "Your projects are ready at ContextSmith")
  end

  def daily_summary_email(user)
    @user = user
    d_tz = Time.current.yesterday.strftime('%F')

    where = " between to_timestamp(#{Time.zone.parse(d_tz).utc.to_i}) and (to_timestamp(#{Time.zone.parse(d_tz).utc.to_i}) + interval '24 hours')"
    
    activities_today = Project.visible_to(user.organization_id, user.id).following(user.id).eager_load([:activities, :account]).where("activities.last_sent_date" + where).group("activities.id, accounts.id")
    @projects_with_activities_today = activities_today.group_by{|e| e.activities}

    @pinned_activities_today = Project.visible_to(user.organization_id, user.id).eager_load([:activities]).where("activities.is_pinned = true and activities.pinned_at" + where).group("activities.id")

    track user: user # ahoy_email tracker
    mail(to: user.email, subject: "Daily Summary for #{Time.current.yesterday.strftime('%A, %B %d')}")
  end

end
