class SessionsController < Devise::SessionsController
  response.headers["X-FRAME-OPTIONS"] = "ALLOW-FROM na30.salesforce.com"
  respond_to :html

  def destroy
    reset_session
    super
  end

end