require 'oauth2'
require 'Time'

class BaseCampService

	client_id = ENV['basecamp_client_id']
	client_secret = ENV['basecamp_client_secret']
	basecamp_authorization_url = ENV['basecamp_authorization_url']
	basecamp_token_url = ENV['basecamp_token_url']
	site = 'https://launchpad.37signals.com/authorization/new?type=web_server'
	refresh_endpoint = 'https://launchpad.37signals.com/authorization/token'
	@redirect_uri = ENV['basecamp_redirect_uri']

	@client = OAuth2::Client.new( client_id, client_secret, :authorize_url => basecamp_authorization_url, :token_url => basecamp_token_url, :site => site)

	oauth_access_tok = "BAhbB0kiAbB7ImNsaWVudF9pZCI6ImE3MDg3MzdmYWFjNjQyNDAzYTNiOGZiMDAwNTg1YWNlNDlmZDE5MzUiLCJleHBpcmVzX2F0IjoiMjAxNy0wMy0xNVQxOToyODozOVoiLCJ1c2VyX2lkcyI6WzMxNDU0MTI3XSwidmVyc2lvbiI6MSwiYXBpX2RlYWRib2x0IjoiNzQwMGQ4ZDM5Y2UwMmFlYTU0MTA5YzZlNzNmMTZlYjYifQY6BkVUSXU6CVRpbWUN80kdwMG3fHIJOg1uYW5vX251bWkCSgI6DW5hbm9fZGVuaQY6DXN1Ym1pY3JvIgdYYDoJem9uZUkiCFVUQwY7AEY=--7c48e98e159d8b33896f31639e1ca9db6253b92a"
	oauth_refresh_tok = "BAhbB0kiAbB7ImNsaWVudF9pZCI6ImE3MDg3MzdmYWFjNjQyNDAzYTNiOGZiMDAwNTg1YWNlNDlmZDE5MzUiLCJleHBpcmVzX2F0IjoiMjAyNy0wMy0wMVQxOToyODozOVoiLCJ1c2VyX2lkcyI6WzMxNDU0MTI3XSwidmVyc2lvbiI6MSwiYXBpX2RlYWRib2x0IjoiNzQwMGQ4ZDM5Y2UwMmFlYTU0MTA5YzZlNzNmMTZlYjYifQY6BkVUSXU6CVRpbWUNM8gfwOLIfHIJOg1uYW5vX251bWkVOg1uYW5vX2RlbmkGOg1zdWJtaWNybyIHAWA6CXpvbmVJIghVVEMGOwBG--eb9a25fde7336ac85293c075655363a42bdf3576"

	# puts "https://launchpad.37signals.com/authorization/token?type=refresh&refresh_token=#{refresh_token}&client_id=#{client_id}&redirect_uri=#{redirect_uri}&client_secret=#{client_secret}"
	

	# puts "Running Basecamp Refresh Check==============================="

	# 	puts "hello"
	# 	puts "attempting to get a new refresh token...."
	# 	def self.to_params
	# 		{
 #    'client_id' => ENV['google_client_id'],
 #    'client_secret' => ENV['google_client_secret'],
 #    'grant_type' => 'refresh_token'}
	# 	end

	# 	client = OAuth2::Client.new( ENV['basecamp_client_id'],
	# 									ENV['basecamp_client_secret'], 
	# 									:authorize_url => ENV['basecamp_authorization_url'], 
	# 									:token_url => ENV['basecamp_token_url'], 
	# 									:site => 'https://launchpad.37signals.com/authorization/new?type=web_server')

	# 	token = OAuth2::AccessToken.from_hash client, {:access_token => oauth_access_tok, :refresh_token => oauth_refresh_tok, :client_id => "a708737faac642403a3b8fb000585ace49fd1935", :client_secret =>"efd66e0c5c0ad9b43d5332646d994bf6eb4334a6" }
	# 	response  = token.post('https://launchpad.37signals.com/authorization/token?type=web_server',
	# 						 :type => 'refresh',
	# 						 :refresh_token => oauth_refresh_tok,
	# 						 :client_id => 'a708737faac642403a3b8fb000585ace49fd1935',
	# 						 :client_secret => client_secret)

 #    refreshhash = JSON.parse(response.body)
 #    puts refreshhash

		# puts "https://launchpad.37signals.com/authorization/token?type=refresh&refresh_token=(1)&client_id=(2)&redirect_uri=(3)&client_secret=(4)"

		

		
		# Sleep until the Token is expired
		# sleep token.expires_at - Time.new.to_i
		# Expect this to return true
		# puts token.expired? # Prints false
		# puts token.expires_at
		# token = token.refresh! if token.expired?

		# This request fails due to expired Token
		puts " Concludes Refresh Test"
		puts "Good bye========================="


	def self.refresh_token(oauth2_token)
		puts "attempting to get a new access token token...."
		token = OAuth2::AccessToken.from_hash(@client, {:access_token => oauth2_token})
		
		if token.expired?
			new_token = token.to_hash
		else
			puts "Token is not expired..."
		end
		new_token
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


	def self.set_access_token(oauth2_token)
		client = OAuth2::Client.new( ENV['basecamp_client_id'],
												ENV['basecamp_client_secret'], 
												:authorize_url => ENV['basecamp_authorization_url'], 
												:token_url => ENV['basecamp_token_url'], 
												:site => 'https://launchpad.37signals.com/authorization/new?type=web_server')
		OAuth2::AccessToken.from_hash client, {:access_token => oauth2_token}
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

	def self.basecamp2_user_project_events(oauth2_token, project_id, instance_url)
		token = set_access_token(oauth2_token)
		result = []
		(1..40).each do |num|
			req = JSON.parse(token.get("#{instance_url}/projects/#{project_id}/events.json?page=#{num}", :params => {'query_foo' => 'bar'}).body)
			req.each { |a| result << a }
			break if req.size < 50
		end
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





end


