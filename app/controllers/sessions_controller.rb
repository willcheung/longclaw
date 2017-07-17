class SessionsController < Devise::SessionsController

  # SessionsController overridden here to handle login errors for Exchange users only
  def new
    # flash[:alert] contains errors when failing oathkeeper_authenticatable strategy
    auth_error = flash[:alert]
    if auth_error.present? && auth_error != 'You need to sign in or sign up before continuing.'
      if auth_error[0..18] == 'The request failed.' # hostname was provided but auth request unsuccessful
        if auth_error[-17..-1] == '(401)Unauthorized' # email+hostname was found, but password incorrect
          @error = 'The password you entered is incorrect. Try again.'
          @hostname = true if params[:user][:hostname]
        else # if auth_error[-4..-1] == 'null' || auth_error[-14..-1] == '(404)Not found' # hostname was empty string or email+hostname was not found
          @error = 'Error: User could not be resolved with current hostname. Please input a new hostname or leave hostname blank to try autodiscover.'
          @hostname = true
        end
      elsif auth_error == 'Invalid credentials' # hostname was autodiscovered, but password incorrect
        @error = 'The password you entered is incorrect. Try again.'
      elsif auth_error == 'Unable to auto-discover the URL' # hostname could not be autodiscovered from e-mail
        @error = 'Error: Hostname could not be found for this user. Please input a hostname or try another username.'
        @hostname = true
      else
        @error = auth_error
      end
    end

    super
  end
  
  # SessionsController overridden here to create new users for Exchange login only, Google login users handled in OmniauthCallbacksController
  def create      
    resource = warden.authenticate!(auth_options)
    resource = resource_class.update_for_oathkeeper_auth(resource, sign_in_params, (cookies[:timezone] || 'UTC'))
    # not sure why, but session not started properly after warden.authenticate! if signing up a new user
    # current workaround is to sign out here and sign in again below, which means the user.sign_in_count will be double the actual number
    sign_out(resource) 
    # puts signed_in?(:user) # puts true for some reason, even though user should be signed out here

    if resource.persisted?
      puts "Exchange login success for user " + resource.email
      flash[:notice] = "Welcome, #{resource.first_name}!"
      sign_in(resource_name, resource)
      respond_with resource, location: after_sign_in_path_for(resource)
    else
      reset_session
      clean_up_passwords resource
      set_minimum_password_length
      puts "Can't persist user!"
      ahoy.track("Error logging in", message: "Can't persist user!")
      redirect_to new_user_registration_path
    end
  end

  protected

  def sign_in_params
    devise_parameter_sanitizer.for(:sign_in) << :hostname
    super
  end

end