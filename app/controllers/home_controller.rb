class HomeController < ApplicationController
  layout 'empty', only: 'access_denied'

  def index
  end

  def access_denied
    # Nothing here
  end

  def thank_you_bak
  	@title = "Welcome to ContextSmith"

  	base_url = "http://64.201.248.178:8888/newsfeed/create"
  	token = current_user.oauth_access_token
  	email = current_user.email
  	start_date = (Time.now.to_i - 1209600).to_s
  	end_date = Time.now.to_i.to_s

  	if ENV["RAILS_ENV"] == 'production'
  		callback_base_url = "http://app.contextsmith.com"
  	elsif ENV["RAILS_ENV"] == 'test'
  		callback_base_url = "https://guarded-refuge-6063.herokuapp.com"
  	elsif ENV["RAILS_ENV"] == 'development'
  		callback_base_url = "http://localhost:3000"
  	end
  	
  	callback = callback_base_url + "/users/#{current_user.id}/send_beta_teaser_email.json"

  	puts callback
  	puts token
  	puts email
  	puts start_date
  	puts end_date

  	final_url = base_url + "?token=" + token + "&after=" + start_date + "&before=" + end_date + "&callback=" + callback + "&email=" + email + "&max=10000"
  	logger.info "Calling remote service: " + final_url

  	url = URI.parse(final_url)
		req = Net::HTTP::Get.new(url.to_s)
		res = Net::HTTP.start(url.host, url.port) { |http| http.request(req) }
		logger.info "Remote service response: " + res.body.to_s
  end
end