require 'oauth2'
class BaseCampService
		# client_id = ENV['basecamp_client_id']
		# client_secret = ENV['basecamp_client_secret']
	@client = nil
	def self.connect_basecamp2
		client_id = 'a708737faac642403a3b8fb000585ace49fd1935'
  		client_secret = 'efd66e0c5c0ad9b43d5332646d994bf6eb4334a6'
		redirect_uri = 'http://localhost:3000/users/auth/37signals/callback'

		basecamp_authorization_url = 'https://launchpad.37signals.com/authorization/new'
  		basecamp_token_url = 'https://launchpad.37signals.com/authorization/token'
  		site = 'https://launchpad.37signals.com/authorization/new?type=web_server'

		puts "Hello from Basecamp Services! How can we help?" 
  		# Create a Client
		@client = OAuth2::Client.new( client_id, client_secret, :authorize_url => basecamp_authorization_url, :token_url => basecamp_token_url, :site => 'https://launchpad.37signals.com/authorization/new?type=web_server')
		
		#open the link
		puts "#{@client.auth_code.authorize_url(redirect_uri: redirect_uri)}"
		#Get this link to the view
		@client.auth_code.authorize_url(redirect_uri: redirect_uri)
		# system("open", client.auth_code.authorize_url(redirect_uri: redirect_uri))
		# Redirect the application to Authorization Page
		# => https://launchpad.37signals.com/authorization/new?client_id=a708737faac642403a3b8fb000585ace49fd1935&redirect_uri=http%3A%2F%2Flocalhost%3A3000%2Foauth2%2Fbasecamp%2Fcallback&response_type=code&type=web_server

		# Verfication code can be obtained through params[:id]

		# Get the access token oject( Authorization code is givein from the pervious step)
		# token = client.auth_code.get_token('authorization_code_value',:redirect_uri => 'http://localhost:3000/oauth')
		# token = client.auth_code.get_token(pin, redirect_uri: redirect_uri, :headers => {'Authorization' => 'Basic some_password'})
		# puts "this is the access_token: #{token.inspect}"
		# token.expires_at
		# Note expires_at is in Epoch(seconds)
		# Note that Verfication code is single-use Only
		# response = token.get('https://launchpad.37signals.com/authorization.json', :params => {'query_foo' => 'bar'})
		# result = JSON.parse(response.body)
		# puts "========"
		# puts result.body
		# puts "======="
		# Parsing through information
		
		# Get the username User who validated
		# puts "#{result['identity']['first_name']}"
		# Get the users Projects
		# response1 = token.get("https://basecamp.com/3643958/api/v1/projects.json", :params => {'query_foo' => 'bar'})
		# puts "This is the User Projects:========="
		# projects = JSON.parse(response1.body)

		# projects.each do |m|
		# 	puts "id: #{m['id']}"
		# 	puts "Project Title: #{m['name']}"
		# 	puts "description: #{m['description']}"
		# end	
		# Get the users topics
		# response2 = token.get("https://basecamp.com/3643958/api/v1/topics.json", :params => {'query_foo' => 'bar'})
		# puts "This is the user messages"
		# topics = JSON.parse(response2.body)

		# topics.each do |m|
		# 	puts "title>> #{m['title']}"	
		# end
		# Get Users Projects Todos:
		# response3 = token.get("https://basecamp.com/3643958/api/v1/projects/13487410/todos.json", :params => {'query_foo' => 'bar'})
		# puts "This is the BaseCamp 2 Intergration Todos"
		# todos = JSON.parse(response3.body)

		# todos.each do |m|
		# 	puts "Todo: #{m['content']}"
		# end
		# puts "This concludes Basecamps Services :))"
	end

	def self.basecamp2_token(token)
		redirect_uri = 'http://localhost:3000/users/auth/37signals/callback'
		puts "this is the basecamp2 token"
		puts "this is this token #{token} and this is the client:#{@client} "
		# Get the access token oject( Authorization code is givein from the pervious step)
		# token = client.auth_code.get_token('authorization_code_value',:redirect_uri => 'http://localhost:3000/oauth')
		if @client != nil
		token = @client.auth_code.get_token(token, redirect_uri: redirect_uri, :headers => {'Authorization' => 'Basic some_password'})
		# token.expires_at
		# Note expires_at is in Epoch(seconds)
		# Note that Verfication code is single-use Only
		response = token.get('https://launchpad.37signals.com/authorization.json', :params => {'query_foo' => 'bar'})
		puts "getting a response...."
		result = JSON.parse(response.body)
		end

	end


end


