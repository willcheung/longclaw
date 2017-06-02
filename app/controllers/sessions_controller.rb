class SessionsController < Devise::SessionsController  

  def new
    p 'Our SessionsController#new'
    super
  end
  
  def destroy
    p 'Our SessionsController#destroy'
    super
  end
  
  def create
    p 'Our SessionsController#create'
    super
  end

end