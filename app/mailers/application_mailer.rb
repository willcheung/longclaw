class ApplicationMailer < ActionMailer::Base
  default from: "no-reply@contextsmith.com"
  layout 'mailer'
end
