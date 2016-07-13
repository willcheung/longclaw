class SessionsController < Devise::SessionsController  
  respond_to :html

  def new 	
  	super
  end
  def destroy
    reset_session
    super
  end

end