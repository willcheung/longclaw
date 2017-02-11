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

	def link_basecamp2_account
			# links the Contextsmith Accounts with the Basecamp2 Projects
	    # One CS Account can link to many BaseCamp2 Accounts
    if params[:basecamp_account_id] && params[:account_id] && params[:project_id]
    	# Check if row already exists in our table
    	tier = Integration.where(:external_account_id=>params[:basecamp_account_id]).where(:project_id=>params[:project_id])
    	if tier.exists?
    		# if ContextSmith Row is Empty fill it with an account_id
    		if tier.first['contextsmith_account_id'] == nil
    			# Check if Activity is already occupied by another project_id
    			if update_activity_project_id(params[:basecamp_account_id], params[:project_id])
    				# Insert account_id into Contextsmith_account_id
    				tier.first['contextsmith_account_id'] = params[:account_id]
    				tier.first.save
    			else
    				#flash if occupied
    				flash[:warning] = "Connection is Occupied"
    			end
    		else
    			# error when link exists
    			flash[:warning] = "Link Already Exists"
    		end
    	else
    		# If there are no existing records that match a basecamp_account and project_id than execute code below
    		begin
    			# Create a new row
	    		Integration.link_basecamp2(params[:basecamp_account_id], params[:account_id], params[:external_name], current_user, params[:project_id])
	    		update_activity_project_id(params[:basecamp_account_id], params[:project_id])
	    	rescue
					#code that deals with some exception
					flash[:error] = "Failed to Create Connection!"
				else
					#code that runs only if (no) excpetion was raised
					flash[:notice] = "Project Synced!"
				end
			end
		end
    redirect_to settings_basecamp2_activity_path
	end

	def update_activity_project_id(basecamp_account_id, project_id)
		tier = Activity.where(:backend_id=>params[:basecamp_account_id]).where(:posted_by => current_user.id)
		unless tier.empty?
			if tier.first['project_id'] == '00000000-0000-0000-0000-000000000000'
				tier.first['project_id'] = params[:project_id]
				tier.first.save
			else tier.first['project_id']
				false
			end
		end
	end

	def remove_basecamp2_account
		basecamp_link = Integration.find_by(id: params["id"])
		basecamp_link.contextsmith_account_id =  nil
		if !basecamp_link.nil?
			tier2 = Activity.where(:project_id => basecamp_link['project_id']).where(:backend_id => basecamp_link['external_account_id'])
			unless tier2.empty?
				if tier2.first['project_id']
					tier2.first['project_id'] = '00000000-0000-0000-0000-000000000000'
					if tier2.first.valid?
						tier2.first.save
					end
				end
			end
			basecamp_link.save
		end
		respond_to do |format|
      format.html { redirect_to settings_basecamp_path }
    end
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

	def self.disconnect
		puts "this is the disconnect basecamp button"
		redirect_to settings_basecamp_path
	end


end
