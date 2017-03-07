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
		result
	end


	def self.load_basecamp2_events_from_backend(oauth_user, project, user_id='00000000-0000-0000-0000-000000000000')

		response = basecamp2_user_project_events(oauth_user, project['external_account_id'])
		object_info = response
		eventable_id_list = response
		list = []
		object_info.each do |y|
			creator_info = BaseCampService.basecamp2_user_info( y['creator']['id'],oauth_user['oauth_access_token'],oauth_user['oauth_instance_url'] )
			user_email = Hash.new
			user_email['user_email'] = creator_info['email_address']
			y.merge!(user_email)
		end
		eventable_id_list.each { |x| list << x['eventable']['id'] }
		list.uniq!
		if list
			list.each do |a|
				result = object_info.select { |b| b['eventable']['id'] == a }							
				result.sort_by { |hash| hash['updated_at'].to_i }
				record = Activity.find_by(:backend_id => a)

				if record.nil?
					Activity.load_basecamp2_activities( result ,project['external_account_id'], user_id, project['contextsmith_account_id'] )
				else
					if record.email_messages.size < result.size
						record.email_messages = result
						record.last_sent_date = result.first['updated_at'].to_datetime
						record.last_sent_date_epoch = result.first['updated_at'].to_datetime.to_i
						record.save
					end 
				end
			end
		end # End list
	end # End Load Basecamp Events

	def self.basecamp2_user_info(id,oauth2_token, instance_url)
		JSON.parse(set_access_token(oauth2_token).get("#{instance_url}/people/#{id}.json", :params => {'query_foo' => 'bar'}).body)
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

	def self.basecamp2_user_projects(oauth2_token, instance_url)
		JSON.parse(set_access_token(oauth2_token).get("#{instance_url}/projects.json", :params => {'query_foo' => 'bar'}).body)
	end




end


