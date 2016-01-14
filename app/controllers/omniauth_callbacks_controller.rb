class OmniauthCallbacksController < Devise::OmniauthCallbacksController   
	def google_oauth2
    @user = User.find_for_google_oauth2(request.env["omniauth.auth"], current_user)
 
    if @user.persisted?
    	session["devise.google_data"] = request.env["omniauth.auth"]
      @user.refresh_token! if @user.token_expired?
      logger.info "Google devise.omniauth_callbacks.success for user " + @user.email
      flash[:notice] = "Welcome, #{@user.first_name}!"

      if @user.cluster_create_date.nil?
        # Kick off cluster analysis to backend
      end

      sign_in_and_redirect @user, :event => :authentication
    else
      reset_session
  		logger.error "Can't persist user!"
      ahoy.track("Error logging in", message: "Can't persist user!")
  		redirect_to new_user_registration_path
    end
  end

  def failure
  	reset_session
  	logger.error "Can't verify Google!"
    ahoy.track("Error logging in", message: "Can't verify Google!")
  	redirect_to new_user_registration_path
  end
end