class OmniauthCallbacksController < Devise::OmniauthCallbacksController   
	def google_oauth2
    allowed_emails = %w(willycheung@gmail.com indifferenzetester@gmail.com rcwang@gmail.com)
    auth = request.env["omniauth.auth"]

    if auth.info.email.include?('gmail.com') and !allowed_emails.include?(auth.info.email)
      redirect_to home_access_denied_path
      return
    end

    @user = User.find_for_google_oauth2(auth, (cookies[:timezone] || 'UTC'))
 
    if @user.persisted?
    	session["devise.google_data"] = auth
      logger.info "Google devise.omniauth_callbacks.success for user " + @user.email
      flash[:notice] = "Welcome, #{@user.first_name}!"

      if @user.cluster_create_date.nil?
        # Kick off cluster analysis to backend
        get_emails_from_backend_with_callback(@user)
      end

      sign_in_and_redirect @user, :event => :authentication
    else
      reset_session
  		logger.error "Can't persist user!"
      ahoy.track("Error logging in", message: "Can't persist user!")
  		redirect_to new_user_registration_path
    end
  end

  def google_apps_marketplace # Not using this right now!
    auth = request.env["omniauth.auth"]
    puts "google_apps_marketplace!!!"
    puts auth

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

    @user = User.find_for_google_oauth2(auth, (cookies[:timezone] || 'UTC'))
    if @user.persisted?
      session["devise.google_data"] = auth
      logger.info "Google devise.google_apps_marketplace.success for user " + @user.email
      flash[:notice] = "Welcome, #{@user.first_name}!"
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
  	redirect_to new_user_registration_path, :flash => { :error => "Can't login using your Google account. Your administrator may need to grant access for you." }
  end

  private

  def get_emails_from_backend_with_callback(user)
    max=10000
    base_url = ENV["csback_base_url"] + "/newsfeed/cluster"

    if ENV["RAILS_ENV"] == 'production'
      callback_url = "https://app.contextsmith.com/onboarding/#{user.id}/create_clusters.json"
      user.refresh_token! if user.token_expired?
      token_emails = [{ token: user.oauth_access_token, email: user.email }]
      in_domain = ""
    elsif ENV["RAILS_ENV"] == 'test' # DEBUG
      callback_url = "https://guarded-refuge-6063.herokuapp.com/onboarding/#{user.id}/create_clusters.json"
      user.refresh_token! if user.token_expired?
      token_emails = [{ token: user.oauth_access_token, email: user.email }]
      in_domain = (user.email == 'indifferenzetester@gmail.com' ? "&in_domain=comprehend.com" : "")
    else # Dev environment
      callback_url = "http://24.130.10.244:3000/onboarding/#{user.id}/create_clusters.json"
      u = User.find_by_email('indifferenzetester@gmail.com')
      u.refresh_token! if u.token_expired?
      token_emails = [{ token: u.oauth_access_token, email: u.email }]
      in_domain = "&in_domain=comprehend.com"
    end
    
    final_url = base_url + "?token_emails=" + token_emails.to_json + "&preview=true&max=" + max.to_s + "&callback=" + callback_url + in_domain
    logger.info "Calling backend service: " + final_url
    ahoy.track("Calling backend service", service: "newsfeed/cluster", final_url: final_url)

    url = URI.parse(final_url)
    req = Net::HTTP::Get.new(url.to_s)
    res = Net::HTTP.start(url.host, url.port) { |http| http.request(req) }
  end
end