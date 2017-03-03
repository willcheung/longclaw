require 'oauth2'
require 'Time'

class BaseCampService

	client_id = ENV['basecamp_client_id']
	client_secret = ENV['basecamp_client_secret']
	basecamp_authorization_url = ENV['basecamp_authorization_url']
	basecamp_token_url = ENV['basecamp_token_url']
	site = 'https://launchpad.37signals.com/authorization/new?type=web_server'
	@redirect_uri = ENV['basecamp_redirect_uri']
	@client = OAuth2::Client.new( client_id, client_secret, :authorize_url => basecamp_authorization_url, :token_url => basecamp_token_url, :site => site)
	
	# def self.get_events_from_backend_with_callback(user)
 #    max=10000
 #    base_url = ENV["csback_base_url"] + "/newsfeed/cluster"

 #    if Rails.env.production?
 #      callback_url = "#{ENV['BASE_URL']}/onboarding/#{user.id}/create_clusters.json"
 #      user.refresh_token! if user.token_expired?
 #      token_emails = [{ token: user.oauth_access_token, email: user.email }]
 #      in_domain = ""
 #    elsif Rails.env.test? # Test / DEBUG 
 #      callback_url = "#{ENV['BASE_URL']}/onboarding/#{user.id}/create_clusters.json"
 #      user.refresh_token! if user.token_expired?
 #      token_emails = [{ token: user.oauth_access_token, email: user.email }]
 #      in_domain = (user.email == 'indifferenzetester@gmail.com' ? "&in_domain=comprehend.com" : "")
 #    else # Dev environment
 #      callback_url = "http://localhost:3000/onboarding/#{user.id}/create_clusters.json"
 #      u = OauthUser.find_by(oauth_provider_uid: user.oauth_provider_uid)

 #      u.refresh_token! if u.token_expired?

 #      token_emails = [{ token: u.oauth_access_token, email: u.email }]
 #      in_domain = "&in_domain=comprehend.com"
 #    end
    ### TODO: add "&request=true" to final_url
    # final_url = base_url + "?token_emails=" + token_emails.to_json + "&preview=true&time=true&neg_sentiment=0&cluster_method=BY_EMAIL_DOMAIN&max=" + max.to_s + "&callback=" + callback_url + in_domain
    # puts "Calling backend service for clustering: " + final_url
    #puts "Callback URL set as: " + callback_url

    # url = URI.parse(final_url)
    # req = Net::HTTP::Get.new(url.to_s)
    # res = Net::HTTP.start(url.host, url.port) { |http| http.request(req) }
  # end

	def self.set_access_token(oauth2_token)
		client = OAuth2::Client.new( ENV['basecamp_client_id'],
												ENV['basecamp_client_secret'], 
												:authorize_url => ENV['basecamp_authorization_url'], 
												:token_url => ENV['basecamp_token_url'], 
												:site => 'https://launchpad.37signals.com/authorization/new?type=web_server')
		OAuth2::AccessToken.from_hash client, {:access_token => oauth2_token}
	end
	
	# Returns a authentication url site
	def self.connect_basecamp2
		@client.auth_code.authorize_url(redirect_uri: @redirect_uri)
	end

	def self.basecamp2_create_user(authorization_code_value)

			token = @client.auth_code.get_token(authorization_code_value, redirect_uri: ENV['basecamp_redirect_uri'], :headers => {'Authorization' => 'Basic some_password'})
			call = token.get('https://launchpad.37signals.com/authorization.json', :params => {'query_foo' => 'bar'})
			response = JSON.parse(call.body)

			new_user = {
					"oauth_provider" => 'basecamp2',
					"oauth_provider_uid" => response['identity']['id'],
					"oauth_access_token" => token.token,
					"oauth_refresh_token" => token.refresh_token,
					"oauth_instance_url" => response['accounts'].first['href'],
					"oauth_user_name" => response['identity']['first_name'] + ' ' + response['identity']['last_name'],
					"oauth_refresh_date" => token.expires_at
				}
		new_user
	end

	def self.basecamp2_user_project_events(basecamp_user, project_id)

		basecamp_user = basecamp_user.refresh_token! if basecamp_user.token_expired?

		token = set_access_token(basecamp_user['oauth_access_token'])
			result = []
			(1..40).each do |num|
				req = JSON.parse(token.get("#{basecamp_user['oauth_instance_url']}/projects/#{project_id}/events.json?page=#{num}", :params => {'query_foo' => 'bar'}).body)
				req.each { |a| result << a }
				break if req.size < 50
			end
		# end
		result
	end

	def self.basecamp2_user_project_topics(oauth2_token, project_id, instance_url)
		result = []
		num = 1
		while num != 41
		req = JSON.parse(set_access_token(oauth2_token).get("#{instance_url}/projects/#{project_id}/topics.json?page=#{num}", :params => {'query_foo' => 'bar'}).body)
		req.each { |a| result << a }
		num += 1
			if req.empty? then break
			end
		end
		result
	end

	def self.basecamp2_find_project(oauth2_token, user_id)
		JSON.parse(set_access_token(oauth2_token).get("https://basecamp.com/3643958/api/v1/projects/#{user_id}.json", :params => {'query_foo' => 'bar'}).body)
	end

	def self.basecamp2_user_messages(oauth2_token, project_id, instance_url, message_id)
		JSON.parse(set_access_token(oauth2_token).get("#{instance_url}/projects/#{project_id}/messages/#{message_id}.json", :params => {'query_foo' => 'bar'}).body)
	end

	def self.basecamp2_user_project_todo(oauth2_token, project_id, instance_url, message_id)
		JSON.parse(set_access_token(oauth2_token).get("#{instance_url}/projects/#{project_id}/messages/#{message_id}.json", :params => {'query_foo' => 'bar'}).body)
	end

		def self.basecamp2_user_info(id,oauth2_token, instance_url)
		JSON.parse(set_access_token(oauth2_token).get("#{instance_url}/people/#{id}.json", :params => {'query_foo' => 'bar'}).body)
	end

	def self.basecamp2_user_projects(oauth2_token, instance_url)
		JSON.parse(set_access_token(oauth2_token).get("#{instance_url}/projects.json", :params => {'query_foo' => 'bar'}).body)
	end

	def self.basecamp2_user_todos(oauth2_token)
		JSON.parse(set_access_token(oauth2_token).get("https://basecamp.com/3643958/api/v1/todolists.json", :params => {'query_foo' => 'bar'}).body)
	end

	def self.basecamp2_user_topics(oauth2_token, project_id=nil)
		if project_id == nil
			JSON.parse(set_access_token(oauth2_token).get("https://basecamp.com/3643958/api/v1/topics.json", :params => {'query_foo' => 'bar'}).body)
		else  oauth2_token && project_id
			JSON.parse(set_access_token(oauth2_token).get("https://basecamp.com/3643958/api/v1/projects/#{project_id}/topics.json", :params => {'query_foo' => 'bar'}).body)
		end
	end

end


