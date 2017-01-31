require 'oauth2'
class BaseCampService

	def self.connect_basecamp2
	# Establish a connection with Basecamp2
	client_id = ENV['basecamp_client_id']
	client_secret = ENV['basecamp_client_secret']
	redirect_uri = ENV['basecamp_redirect_uri']
	basecamp_authorization_url = ENV['basecamp_authorization_url']
	basecamp_token_url = ENV['basecamp_token_url']
	site = 'https://launchpad.37signals.com/authorization/new?type=web_server'
	# Create a Client
	# Checks if the user is registered with BaseCamp 2
	@client = OAuth2::Client.new( client_id, client_secret, :authorize_url => basecamp_authorization_url, :token_url => basecamp_token_url, :site => site)
	
	# Link to the site for Users to Authorize Access to ContextSmith
	@client.auth_code.authorize_url(redirect_uri: redirect_uri)
	# Verfication code can be obtained through params[:id]

	end

	def self.basecamp2_create_user(pin)
		
		if @client != nil
			token = @client.auth_code.get_token(pin, redirect_uri: ENV['basecamp_redirect_uri'], :headers => {'Authorization' => 'Basic some_password'})
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
		end
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

	def self.basecamp2_user_projects(pin)
		# redirect_uri = ENV['basecamp_redirect_uri']
		# if @client != nil
		# 	token = @client.auth_code.get_token(pin, redirect_uri: redirect_uri, :headers => {'Authorization' => 'Basic some_password'})
		# 	response1 = token.get("https://basecamp.com/3643958/api/v1/projects.json", :params => {'query_foo' => 'bar'})
		# 	# First request returns up to 50 records
		# 	JSON.parse(response1.body)
		# end
	end

	def self.basecamp2_user_todos(pin)
		# topics.each do |m|
		# 	puts "title>> #{m['title']}"	
		# end
		# Get Users Projects Todos:
		# response3 = token.get("https://basecamp.com/3643958/api/v1/projects/13487410/todos.json", :params => {'query_foo' => 'bar'})
		# puts "This is the BaseCamp 2 Intergration Todos"
		# todos = JSON.parse(response3.body)
		puts "user_todos"
	end

	def self.basecamp2_user_discussions(pin)
		puts "user discussions"
	end

	def self.basecamp2_user_topics(pin)
		# Get the users topics
		# redirect_uri = ENV['basecamp_redirect_uri']
		# if @client != nil
		# 	token = @client.auth_code.get_token(pin, redirect_uri: redirect_uri, :headers => {'Authorization' => 'Basic some_password'})
		# response2 = token.get("https://basecamp.com/3643958/api/v1/topics.json", :params => {'query_foo' => 'bar'})
		# puts "This is the user messages"
		# JSON.parse(response2.body)
		# end
	end


end


