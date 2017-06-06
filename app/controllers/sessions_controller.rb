class SessionsController < Devise::SessionsController  

  def new
    puts 'Our SessionsController#new', '====================='
    super
  end
  
  def destroy
    puts 'Our SessionsController#destroy', '====================='
    super
  end
  
  def create
    puts 'Our SessionsController#create', '====================='
    # self.resource = warden.authenticate!(auth_options)
    # p self
    # p auth_options
    p session
    self.resource = resource_class.new_with_session(hash || {}, session)
    super

    # p self.resource
    # p self.resource.id

    # if resource.id.nil?
    #   p sign_up_params
    #   build_resource(sign_up_params)
    #   p self.resource
    # else
    #   super
    # end
  end

  protected

  # Build a devise resource passing in the session. Useful to move
  # temporary session data to the newly created user.
  def build_resource(hash=nil)
    self.resource = resource_class.new_with_session(hash || {}, session)
  end

  def sign_up_params
    devise_parameter_sanitizer.sanitize(:sign_up)
  end

end