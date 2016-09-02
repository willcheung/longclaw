# == Schema Information
#
# Table name: salesforce_accounts
#
#  id                           :integer          not null, primary key
#  salesforce_account_id        :string           default(""), not null
#  salesforce_account_name      :string           default(""), not null
#  salesforce_updated_at        :datetime
#  contextsmith_account_id      :uuid
#  contextsmith_organization_id :uuid             not null
#  created_at                   :datetime         not null
#  updated_at                   :datetime         not null
#
# Indexes
#
#  index_salesforce_accounts_on_salesforce_account_id  (salesforce_account_id) UNIQUE
#

class SalesforceAccount < ActiveRecord::Base
	belongs_to  :organiztion, foreign_key: "contextsmith_organization_id"
	belongs_to :account, foreign_key: "contextsmith_account_id"


	def self.load(current_user)

		salesforce_client_id = ENV['salesforce_client_id']
    salesforce_client_secret = ENV['salesforce_client_secret'] 
    hostURL = 'login.salesforce.com'  
    # try to get salesforce production. if not connect, check if it is connected to salesforce sandbox
    salesforce_user = OauthUser.find_by(oauth_provider: 'salesforce', organization_id: current_user.organization_id)

    if(salesforce_user.nil?)
    	salesforce_user = OauthUser.find_by(oauth_provider: 'salesforcesandbox', organization_id: current_user.organization_id)
    	salesforce_client_id = ENV['salesforce_sandbox_client_id']
    	salesforce_client_secret = ENV['salesforce_sandbox_client_secret']
	  	hostURL = 'test.salesforce.com' 
  	end

    salesforce_accounts = []

    if(!salesforce_user.nil?)        	
      client = Restforce.new :host => hostURL,
                             :client_id => salesforce_client_id,
                             :client_secret => salesforce_client_secret,
      											 :oauth_token => salesforce_user.oauth_access_token,
      											 :refresh_token => salesforce_user.oauth_refresh_token,
      											 :instance_url => salesforce_user.oauth_instance_url          
         

      begin
      	salesforce_accounts = client.query("select Id, Name, LastModifiedDate from Account")
  
		  rescue  
		  	# salesforce refresh token expires when different app use it for 5 times
		  	salesforce_user.destroy
		  	puts "Error: salesforce error"
		  	respond_to do |format|
    				format.html { redirect_to settings_url }
 				end
		  end 		
    end

    if !salesforce_accounts.nil?
			salesforce_accounts.each do |s|
				if !SalesforceAccount.exists?(salesforce_account_id: s.Id)
					salesforce_account = SalesforceAccount.new(salesforce_account_id: s.Id,
      	      	salesforce_account_name: s.Name,
      	      	contextsmith_organization_id: current_user.organization_id,
      	      	salesforce_updated_at: DateTime.strptime(s.LastModifiedDate, '%Y-%m-%dT%H:%M:%S.%L%z').to_time)

  	      salesforce_account.save
				end
			end
		end

	end

end
