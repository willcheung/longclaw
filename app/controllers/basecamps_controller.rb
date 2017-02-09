require_dependency "app/services/basecamp_service.rb"

class BasecampsController < ApplicationController
	layout "empty", only: [:index]

	def index
	end

	def self.load
		# call this method in order to update any kind of new activity
	end

	def basecamp2
		redirect_to BaseCampService.connect_basecamp2
	end


	@account_id = []

	def map_projects
		puts "Hello this is the maps_projects"
		if params[:account_id]
			puts "this is the account_id: #{params[:account_id]}"
			@account_id = params[:account_id]
		end

		redirect_to settings_basecamp2_projects_path(:account_id => params[:account_id])
	end




	def link_basecamp2_account
		# links the Contextsmith Accounts with the Basecamp2 Projects
	    # One CS Account can link to many BaseCamp2 Accounts
	    if params[:basecamp_account_id] && params[:account_id] && params[:project_id]
	    	begin
	    		Integration.link_basecamp2(params[:basecamp_account_id], params[:account_id], params[:external_name], current_user, params[:project_id])
	    	rescue
				#code that deals with some exception
				flash[:warning] = "Sorry something went wrong"
				else
				#code that runs only if (no) excpetion was raised
				flash[:notice] = "Project Synced!"
				end
			end
	    # end
	    # basecamp2_account = SalesforceAccount.find_by(id: params[:salesforce_id], contextsmith_organization_id: current_user.organization_id)
	    # if !basecamp2_account.nil?
	    #   salesforce_account.account = Account.find_by_id(params[:account_id])
	    #   salesforce_account.save
	    # end

	    # respond_to do |format|
	    #   format.html { redirect_to settings_salesforce_path }
	    # end

	    redirect_to :back
	end




	def refresh_token
	end


	def self.basecamp2_projects(token)
		BaseCampService.basecamp2_user_projects(token)
	end

	def self.basecamp2_topics(token, project_id=nil)
		BaseCampService.basecamp2_user_topics(token)
	end

	def self.basecamp2_user_info(token, project_id = nil)
		BaseCampService.basecamp2_user_info(token)
	end

	def self.basecamp2_user_todos(token)
		BaseCampService.basecamp2_user_todos(token)
	end



end
