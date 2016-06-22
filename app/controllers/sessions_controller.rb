class SessionsController < Devise::SessionsController  
  respond_to :html

  def new 	
  	response.headers["X-FRAME-OPTIONS"] = "ALLOW-FROM na30.salesforce.com"
  	super
  	# response.headers["X-FRAME-OPTIONS"] = "ALLOW-FROM na30.salesforce.com"
  end
  def destroy
    reset_session
    super
  end

end