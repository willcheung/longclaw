class UserMailer < ApplicationMailer
  add_template_helper(MailerHelper)

  def welcome_email(user, num_of_projects, url)
    @user = user
    @num_of_projects = num_of_projects
    @url = url

    track user: user # ahoy_email tracker
    mail(to: @user.email, subject: "Your projects are ready at ContextSmith")
  end

end
