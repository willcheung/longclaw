class UserMailer < ApplicationMailer
  add_template_helper(MailerHelper)

  def welcome_email(user)
  	default from: "\"Will Cheung\" <wcheung@contextsmith.com>"
    @user = user
    mail(to: @user.email, subject: "Welcome to ContextSmith!")
  end

  def beta_teaser_email(user, data)
    # curl -H "Content-Type: application/json" --data @/Users/wcheung/Downloads/contextsmith_project_details.json http://localhost:3000/users/64eb67f6-3ed1-4678-84ab-618d348cdf3a/send_beta_teaser_email.json

    @user = user
    @data = data

    track user: user
    mail(to: @user.email, subject: "Sneak Preview: Projects Recap by ContextSmith")
  end
end
