class ApplicationMailer < ActionMailer::Base
  default from: "\"ContextSmith\" <notifications@contextsmith.com>"
  layout 'mailer'
end
