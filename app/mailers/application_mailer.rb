class ApplicationMailer < ActionMailer::Base
  default from: "\"ContextSmith\" <no-reply@contextsmith.com>"
  layout 'mailer'
end
