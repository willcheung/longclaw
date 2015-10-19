class UserMailer < ApplicationMailer
	default from: "\"ContextSmith\" <no-reply@contextsmith.com>"
 
  def welcome_email(user)
    @user = user
    mail(to: @user.email, subject: "Welcome to ContextSmith!")
  end

  def beta_teaser_email(user)
    @user = user
    mail(to: @user.email, subject: "Sneak Preview: Project Recap by ContextSmith")
  end
end
