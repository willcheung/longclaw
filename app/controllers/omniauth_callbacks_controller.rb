class OmniauthCallbacksController < Devise::OmniauthCallbacksController   
	def google_oauth2
    allowed_emails = %w(willycheung@gmail.com indifferenzetester@gmail.com rcwang@gmail.com)
    auth = request.env["omniauth.auth"]

    if auth.info.email.include?('gmail.com') and !allowed_emails.include?(auth.info.email)
      redirect_to home_access_denied_path
      return
    end

    @user = User.find_for_google_oauth2(auth, current_user)
 
    if @user.persisted?
    	session["devise.google_data"] = auth
      @user.refresh_token! if @user.token_expired?
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

  def failure
  	reset_session
  	logger.error "Can't verify Google!"
    ahoy.track("Error logging in", message: "Can't verify Google!")
  	redirect_to new_user_registration_path
  end

  private

  def get_emails_from_backend_with_callback(user)
    max=10000
    base_url = ENV["csback_base_url"] + "/newsfeed/cluster"

    if ENV["RAILS_ENV"] == 'production'
      callback_url = "http://app.contextsmith.com/onboarding/#{user.id}/create_clusters.json"
      user.refresh_token! if user.token_expired?
      token_emails = [{ token: user.oauth_access_token, email: user.email }]
      in_domain = ""
    else
      # DEBUG
      if ENV["RAILS_ENV"] == 'test'
        callback_url = "https://guarded-refuge-6063.herokuapp.com/onboarding/#{user.id}/create_clusters.json"
        user.refresh_token! if user.token_expired?
        token_emails = [{ token: user.oauth_access_token, email: user.email }]
        in_domain = ""
      else
        callback_url = "http://24.130.10.244:3000/onboarding/#{user.id}/create_clusters.json"
        u = User.find_by_email('indifferenzetester@gmail.com')
        u.refresh_token! if u.token_expired?
        token_emails = [{ token: u.oauth_access_token, email: u.email }]
        in_domain = "&in_domain=comprehend.com"
      end
    end
    
    final_url = base_url + "?token_emails=" + token_emails.to_json + "&max=" + max.to_s + "&callback=" + callback_url + in_domain
    logger.info "Calling backend service: " + final_url
    ahoy.track("Calling backend service", service: "newsfeed/cluster", final_url: final_url)

    url = URI.parse(final_url)
    req = Net::HTTP::Get.new(url.to_s)
    res = Net::HTTP.start(url.host, url.port) { |http| http.request(req) }
  end
end