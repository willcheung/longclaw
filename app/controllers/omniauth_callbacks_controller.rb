class OmniauthCallbacksController < Devise::OmniauthCallbacksController
  def salesforce
    User.from_omniauth(request.env["omniauth.auth"], current_user.organization_id, current_user.id)
    puts "Here in OmniauthCallbacksController@salesforce !!!"
    redirect_to settings_path
  end

  def salesforcesandbox
    User.from_omniauth(request.env["omniauth.auth"], current_user.organization_id, current_user.id)
    redirect_to settings_path
  end

	def google_oauth2
    allowed_emails = %w(willycheung@gmail.com indifferenzetester@gmail.com)
    auth = request.env["omniauth.auth"]

    if auth.info.email.include?('gmail.com') and !allowed_emails.include?(auth.info.email)
      redirect_to home_access_denied_path
      return
    end

    @user = User.find_for_google_oauth2(auth, (cookies[:timezone] || 'UTC'))

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
    puts "Hellow from basecamp2 in Omniauth-callbackcontroller"
  end

  def failure
  	reset_session
  	puts "Error: Oauth verification failure!"
    ahoy.track("Error logging in", message: "Oauth verification failure!")
  	redirect_to new_user_registration_path, :flash => { :error => "Can't login using your Google account. Your administrator may need to grant access for you." }
  end


end
