class UserMailer < ApplicationMailer
  add_template_helper(MailerHelper)

  def welcome_email(user, num_of_projects, url)
    @user = user
    @num_of_projects = num_of_projects
    @url = url
    
    track user: user # ahoy_email tracker
    mail(to: @user.email, subject: "Your projects are ready at ContextSmith")
  end

  def beta_teaser_email(user, data, start_date, end_date)
    # curl -H "Content-Type: application/json" --data @/Users/wcheung/Downloads/contextsmith_project_details.json http://localhost:3000/users/64eb67f6-3ed1-4678-84ab-618d348cdf3a/send_beta_teaser_email.json

    @user = user
    @data = data
    @start_date = start_date
    @end_date = end_date

    track user: user
    mail(to: @user.email, subject: "Projects Recap by ContextSmith")
  end
end
