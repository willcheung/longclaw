class OmniauthCallbacksController < Devise::OmniauthCallbacksController
  def salesforce
    #puts "****** session return_to_path: #{ session[:return_to_path] }"
    User.from_sfdc_omniauth(request.env["omniauth.auth"], current_user)
    set_auto_salesforce_refresh_custom_config(current_user)
    InitialSalesforceLoginsJob.perform_later(current_user)
    redirect_to (session.delete(:return_to_path) || root_path)
  end

  def salesforcesandbox
    User.from_sfdc_omniauth(request.env["omniauth.auth"], current_user)
    set_auto_salesforce_refresh_custom_config(current_user)
    InitialSalesforceLoginsJob.perform_later(current_user)
    redirect_to (session.delete(:return_to_path) || root_path)
  end

  # login for basic users. only requires email/profile scope
  def google_oauth2_basic
    google_oauth2
  end

	def google_oauth2
    auth = request.env["omniauth.auth"]
    request_params = request.env['omniauth.params']
    @user = User.find_for_oauth2(auth, (cookies[:timezone] || 'UTC'))

    if @user.persisted?
    	session["devise.google_data"] = auth
      puts "Google devise.omniauth_callbacks.success for user " + @user.email
      flash[:notice] = "Welcome, #{@user.first_name}!"

      sign_in_and_redirect @user, :event => :authentication
    else
      reset_session
  		puts "Can't persist user!"
      ahoy.track("Error logging in", message: "Can't persist user!")
  		redirect_to new_user_registration_path
    end
  end

  def microsoft_v2_auth
    auth = request.env["omniauth.auth"]
    request_params = request.env['omniauth.params']
    raw = auth.extra.raw_info
    @user = User.find_for_oauth2(auth, (cookies[:timezone] || 'UTC'),  Hashie::Mash.new(
        first_name: raw.givenName,
        last_name: raw.surname,
        email: raw.mail,
        image: ''
    ))

    if @user.persisted?
    	# session["devise.google_data"] = auth
      puts " devise.omniauth_callbacks.success for user " + @user.email
      flash[:notice] = "Welcome, #{@user.first_name}!"

      sign_in_and_redirect @user, :event => :authentication
    else
      reset_session
  		puts "Can't persist user!"
      ahoy.track("Error logging in", message: "Can't persist user!")
  		redirect_to new_user_registration_path
    end
  end

  def google_apps_marketplace # Not using this right now!

    # key = Google::APIClient::PKCS12.load_key(File.join(Rails.root,'config','ContextSmith-3b05307c000d.p12'), 'notasecret')
    # client = Google::APIClient.new

    # client.authorization = Signet::OAuth2::Client.new(
    #         :token_credential_uri => 'https://accounts.google.com/o/oauth2/token',
    #         :audience => 'https://accounts.google.com/o/oauth2/token',
    #         :scope => 'https://www.googleapis.com/auth/calendar',
    #         :issuer => 'contextsmith-service-account@contextsmith.iam.gserviceaccount.com',
    #         :signing_key => key,
    #         :person => auth.info.email)
    # client.authorization.fetch_access_token!

  end

  def basecamp2
    puts "Hello from basecamp2 in Omniauth-callbackcontroller"
  end

  def failure
  	reset_session
  	puts "Error: Oauth verification failure!"
    ahoy.track("Error logging in", message: "Oauth verification failure!")
  	redirect_to new_user_registration_path, :flash => { :error => "Can't log in using your Google account. Your administrator may need to grant access for you." }
  end

  # Correctly redirect to the right page after returning from OAuth call (whether in web app or Chrome extension)
  def user_omniauth_auth_helper
    # Save the redirect path which will be used in the OAuth callback
    session[:return_to_path] = params[:source] == "chrome" ? extension_path(login: true) : URI.escape(request.referer, ".")
    # puts "session[:return_to_path]=#{session[:return_to_path]}"
    redirect_to user_omniauth_authorize_path(params[:provider])
  end

  private

  def set_auto_salesforce_refresh_custom_config(current_user)
    if current_user.admin?
      # oauth_user = SalesforceController.get_sfdc_oauthuser(organization: current_user.organization)
      current_user.organization.custom_configurations.find_or_create_by(config_type: CustomConfiguration::CONFIG_TYPE[:Salesforce_refresh], user_id: nil) do |config|
        config.config_value = true
      end
    else
      # oauth_user = SalesforceController.get_sfdc_oauthuser(user: current_user)
      current_user.organization.custom_configurations.find_or_create_by(config_type: CustomConfiguration::CONFIG_TYPE[:Salesforce_refresh], user_id: current_user.id) do |config|
        config.config_value = true
      end
    end
  end
end
