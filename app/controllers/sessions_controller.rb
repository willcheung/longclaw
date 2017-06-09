class SessionsController < Devise::SessionsController
  # before_filter :authenticate_user!, only: :create

  def new
    puts 'Our SessionsController#new', '====================='
    super
    # p user_signed_in?
    # p user_session
  end
  
  def destroy
    puts 'Our SessionsController#destroy', '====================='
    super
  end
  
  def create
    puts 'Our SessionsController#create', '====================='
    # super do |resource|
    #   resource = resource_class.update_for_oathkeeper_auth(resource, sign_in_params, (cookies[:timezone] || 'UTC'))
    # end
      
    resource = warden.authenticate!(auth_options)
    resource = resource_class.update_for_oathkeeper_auth(resource, sign_up_params, (cookies[:timezone] || 'UTC'))
    puts signed_in?(:user)
    # not sure why, but session not started properly after warden.authenticate! if signing up a new user
    # current workaround is to sign out here and sign in again below, which means the user.sign_in_count will be double the actual number
    sign_out(resource) 
    puts signed_in?(:user) # puts true for some reason, even though user should be signed out here

    if resource.persisted?
      puts "Exchange login success for user " + resource.email
      flash[:notice] = "Welcome, #{resource.first_name}!"
      sign_in(resource_name, resource)
      puts signed_in?(:user)
      respond_with resource, location: after_sign_in_path_for(resource)
    else
      reset_session
      clean_up_passwords resource
      set_minimum_password_length
      puts "Can't persist user!"
      ahoy.track("Error logging in", message: "Can't persist user!")
      redirect_to new_user_registration_path
    end
    # # p user_signed_in?
    # # p user_session
    # p current_user
  end

  protected

  def sign_up_params
    devise_parameter_sanitizer.sanitize(:sign_up)
  end

end