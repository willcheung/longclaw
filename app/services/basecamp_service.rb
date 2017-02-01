require 'oauth2'

class BaseCampService

	client_id = ENV['basecamp_client_id']
	client_secret = ENV['basecamp_client_secret']
	basecamp_authorization_url = ENV['basecamp_authorization_url']
	basecamp_token_url = ENV['basecamp_token_url']
	site = 'https://launchpad.37signals.com/authorization/new?type=web_server'
	@redirect_uri = ENV['basecamp_redirect_uri']

	@client = OAuth2::Client.new( client_id, client_secret, :authorize_url => basecamp_authorization_url, :token_url => basecamp_token_url, :site => site)

	def self.connect_basecamp2
		@client.auth_code.authorize_url(redirect_uri: @redirect_uri)
	end

	def set_access_token
	
	end

	def self.basecamp2_create_user(authorization_code_value)
		puts "basecamp2_create_user call this is the pin: #{authorization_code_value}"

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

	def self.basecamp2_user(pin) 
		# redirect_uri = ENV['basecamp_redirect_uri']
		# Get the access token oject( Authorization code is givein from the pervious step)
		# token = client.auth_code.get_token('authorization_code_value',:redirect_uri => 'http://localhost:3000/oauth')
		# if @client != nil
			# token = @client.auth_code.get_token(pin, redirect_uri: redirect_uri, :headers => {'Authorization' => 'Basic some_password'})
			# token.expires_at
			# Note expires_at is in Epoch(seconds)
			# Note that Verfication code is single-use Only
			# response = token.get('https://launchpad.37signals.com/authorization.json', :params => {'query_foo' => 'bar'})
			# puts "getting a response...."
			# JSON.parse(response.body)
		# end
	end

	def self.basecamp2_user_projects(oauth2_token)

		client = OAuth2::Client.new( ENV['basecamp_client_id'],
																	ENV['basecamp_client_secret'], 
																	:authorize_url => ENV['basecamp_authorization_url'], 
																	:token_url => ENV['basecamp_token_url'], 
																	:site => 'https://launchpad.37signals.com/authorization/new?type=web_server')

		access_token = OAuth2::AccessToken.from_hash client, {:access_token => oauth2_token}
		# token = Oauth2::AccessToken.new(@client, oauth2_token)
		response = access_token.get("https://basecamp.com/3643958/api/v1/projects.json", :params => {'query_foo' => 'bar'})
		# First request returns up to 50 records
		JSON.parse(response.body)
	end

	def self.basecamp2_user_todos(oauth2_token)
		client = OAuth2::Client.new( ENV['basecamp_client_id'],
																	ENV['basecamp_client_secret'], 
																	:authorize_url => ENV['basecamp_authorization_url'], 
																	:token_url => ENV['basecamp_token_url'], 
																	:site => 'https://launchpad.37signals.com/authorization/new?type=web_server')

		access_token = OAuth2::AccessToken.from_hash client, {:access_token => oauth2_token}
		JSON.parse(access_token.get("https://basecamp.com/3643958/api/v1/todolists/completed.json", :params => {'query_foo' => 'bar'}).body)
	end

	def self.basecamp2_user_discussions(pin)
		puts "user discussions"
	end

	def self.basecamp2_user_topics(oauth2_token)
				client = OAuth2::Client.new( ENV['basecamp_client_id'],
																	ENV['basecamp_client_secret'], 
																	:authorize_url => ENV['basecamp_authorization_url'], 
																	:token_url => ENV['basecamp_token_url'], 
																	:site => 'https://launchpad.37signals.com/authorization/new?type=web_server')

		access_token = OAuth2::AccessToken.from_hash client, {:access_token => oauth2_token}
		# First request returns up to 50 records
		JSON.parse(access_token.get("https://basecamp.com/3643958/api/v1//topics.json", :params => {'query_foo' => 'bar'}).body)
	end


end


