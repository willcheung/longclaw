class SessionsController < Devise::SessionsController
  respond_to :html

  def destroy
    reset_session
    super
  end

end