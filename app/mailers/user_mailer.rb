class UserMailer < ApplicationMailer
  def welcome_email(user)
  	default from: "\"Will Cheung\" <wcheung@contextsmith.com>"
    @user = user
    mail(to: @user.email, subject: "Welcome to ContextSmith!")
  end

  def beta_teaser_email(user, content)
    @user = user
    @content = content

    track user: user
    mail(to: @user.email, subject: "Sneak Preview: Project Recap by ContextSmith")
  end
end
