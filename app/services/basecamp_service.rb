require 'oauth2'

class BaseCampService

	client_id = ENV['basecamp_client_id']
	client_secret = ENV['basecamp_client_secret']
	basecamp_authorization_url = ENV['basecamp_authorization_url']
	basecamp_token_url = ENV['basecamp_token_url']
	site = 'https://launchpad.37signals.com/authorization/new?type=web_server'
	@redirect_uri = ENV['basecamp_redirect_uri']

	@client = OAuth2::Client.new( client_id, client_secret, :authorize_url => basecamp_authorization_url, :token_url => basecamp_token_url, :site => site)


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

	#returns a authentication url site
	def self.connect_basecamp2
		@client.auth_code.authorize_url(redirect_uri: @redirect_uri)
	end

	def self.set_access_token(oauth2_token)
		client = OAuth2::Client.new( ENV['basecamp_client_id'],
												ENV['basecamp_client_secret'], 
												:authorize_url => ENV['basecamp_authorization_url'], 
												:token_url => ENV['basecamp_token_url'], 
												:site => 'https://launchpad.37signals.com/authorization/new?type=web_server')
		OAuth2::AccessToken.from_hash client, {:access_token => oauth2_token}
	end


	def self.basecamp2_user_info(oauth2_token)
		JSON.parse(set_access_token(oauth2_token).get("https://basecamp.com/3643958/api/v1/people/me.json", :params => {'query_foo' => 'bar'}).body)
	end


	def self.basecamp2_user_projects(oauth2_token)
		JSON.parse(set_access_token(oauth2_token).get("https://basecamp.com/3643958/api/v1/projects.json", :params => {'query_foo' => 'bar'}).body)
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

	def self.get_events(oauth2_token)
		# All actions in Basecamp generate an event for the progress log.
		# If you start a new to-do list, there's an event. 
		# If you give someone access to a project, there's an event. If you add a comment. You get the drill.
		# If you're using this API for polling, please make sure that you're using the since parameter to limit the result set.
		#  Use the created_at time of the first item on the list for subsequent polls. If there's nothing new since that date, you'll get [] back.

		JSON.parse(set_access_token(oauth2_token).get("https://basecamp.com/3643958/api/v1/projects.json", :params => {'query_foo' => 'bar'}).body)

	end

	def self.basecamp2_user_project_events(oauth2_token, user_id)
		JSON.parse(set_access_token(oauth2_token).get("https://basecamp.com/3643958/api/v1/projects/#{user_id}/events.json", :params => {'query_foo' => 'bar'}).body)
	end


	# take in a current user.
	# save in basecamp user information(tokens/refresh)
	# get user infromation
	# get user projects
	# save each users projects in activities modal labeled "basecamp2"
	# create 1 to 1 relationship 

	def self.expired?
		
	end



end


