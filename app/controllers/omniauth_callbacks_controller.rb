class OmniauthCallbacksController < Devise::OmniauthCallbacksController   
	def google_oauth2
    @user = User.find_for_google_oauth2(request.env["omniauth.auth"], current_user)
 
    if @user.persisted?
    	session["devise.google_data"] = request.env["omniauth.auth"]
      flash[:notice] = I18n.t "devise.omniauth_callbacks.success", :kind => "Google"
      sign_in_and_redirect @user, :event => :authentication
    else
      reset_session
  		flash[:error] = "Can't verify Google!"
  		redirect_to new_user_registration_path
    end
  end

  def failure
  	reset_session
  	flash[:error] = "Can't verify Google!"
  	redirect_to new_user_registration_path
  end
end