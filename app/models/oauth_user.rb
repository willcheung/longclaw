# == Schema Information
#
# Table name: oauth_users
#
#  id                  :integer          not null, primary key
#  oauth_provider      :string           not null
#  oauth_provider_uid  :string           not null
#  oauth_access_token  :string           not null
#  oauth_refresh_token :string
#  oauth_instance_url  :string           not null
#  oauth_user_name     :string           default(""), not null
#  organization_id     :uuid             not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  oauth_refresh_date  :integer
#  oauth_issued_date   :datetime
#
# Indexes
#
#  oauth_per_user  (oauth_provider,oauth_user_name,oauth_instance_url) UNIQUE
#

require 'net/http'

class OauthUser < ActiveRecord::Base
	belongs_to 	:organization
	belongs_to :user
	has_many :integrations, dependent: :destroy

	scope :basecamp_user, -> {where oauth_provider: CATEGORY[:basecamp2] }
	
	CATEGORY = { basecamp2: 'basecamp2', salesforce: 'salesforce' }
	

	def self.basecamp2_create_user(pin, organization_id, current_id)

		result = BasecampService.basecamp2_create_user(pin)

		if result
			# Find if the client already saved in Oauthuser exists
			client = OauthUser.find_by(:organization_id => organization_id, oauth_provider_uid: result['oauth_provider_uid'] )
			if !client.nil?
				
			else
				user = OauthUser.new(
				oauth_provider: result['oauth_provider'],
				oauth_provider_uid: result['oauth_provider_uid'],
				oauth_access_token: result['oauth_access_token'],
				oauth_refresh_token: result['oauth_refresh_token'],
				oauth_instance_url: result['oauth_instance_url'],
				oauth_user_name: result['oauth_user_name'],
				organization_id: organization_id,
				oauth_refresh_date: result['oauth_refresh_date'],
				oauth_issued_date: Time.now
				)

				if user.valid?
					user.save
				end
			end
		else
			flash[:error] = "User Not Found at BaseCamp2"
		end # If !client.nil?

	end # Ends method

	def self.basecamp2_projects(token, url)
		BasecampService.basecamp2_user_projects(token, url)
	end


	# BaseCamp2 Refresh methods
	def to_params    
    {'refresh_token' => oauth_refresh_token,
    'client_id' => ENV['basecamp_client_id'],
    'client_secret' => ENV['basecamp_client_secret'],
    'type' => 'refresh',
    'redirect_uri' => ENV['basecamp_redirect_uri']
  	}
  end

  def request_token_from_basecamp2
    url = URI("https://launchpad.37signals.com/authorization/token?type=refresh")
    Net::HTTP.post_form(url, self.to_params)
  end

  def refresh_token!
    response = request_token_from_basecamp2
    data = JSON.parse(response.body)

    if data['access_token'].nil?
      puts "Access_token nil while refreshing token for user #{oauth_user_name}"
      return false
    else
      update_attributes(
        oauth_access_token: data['access_token'],
        oauth_refresh_date: Time.now.to_i + data['expires_in']
        )
      return self
    end
  end

  def token_expired?
  	puts "Checking if token expired?"
    oauth_refresh_date < Time.now.to_i
  end

  def fresh_token
    refresh_token! if token_expired?
    oauth_access_token
  end

end









