require_dependency "app/services/basecamp_service.rb"

class BasecampsController < ApplicationController
	layout "empty", only: [:index]

	def index
	end

	def self.load
		# call this method in order to update any kind of new activity
	end

	def basecamp2
		respond_to do |format|
		format.html { redirect_to BaseCampService.connect_basecamp2}
		end
	end

	def link_basecamp2_account
		if params[:basecamp_account_id] && params[:account_id] && params[:basecamp_account_id] != "" && params[:account_id] != ""

			basecamp2_user = OauthUser.find_by(oauth_provider: 'basecamp2', organization_id: current_user.organization_id)
			basecamp_project_name = BaseCampService.basecamp2_find_project(basecamp2_user['oauth_access_token'], params[:basecamp_account_id] )
    	tier = Integration.where(:contextsmith_account_id => params[:account_id])
    	tier2 = Integration.where(:external_account_id => params[:basecamp_account_id])

    	if tier.any? || tier2.any?
    		flash[:warning] = "Connection is Occupied"
    	else
    		begin
	    		Integration.link_basecamp2(params[:basecamp_account_id], params[:account_id], basecamp_project_name['name'], current_user, params[:project_id])
	    	rescue
					flash[:error] = "Failed to Create Connection!"
				else
					flash[:notice] = "Projects Linked!"
				end
			end
		end
    respond_to do |format|
      format.html { redirect_to settings_basecamp_path }
    end 

	end

	

	def remove_basecamp2_account
		basecamp_link = Integration.find_by(id: params["id"])
		if basecamp_link.valid?
			begin
			act_list = Activity.where(:category => "Basecamp2").where(:project_id => basecamp_link['contextsmith_account_id'])
			if act_list
				act_list.each do |a|
					a.destroy
				end
			end
			basecamp_link.destroy
		else
			flash[:notice] = "Link Removed!"
		end
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

	def refresh_accounts
		@streams = Project.visible_to_admin(current_user.organization_id).is_active.includes(:salesforce_opportunity) # all active projects because "admin" role can see everything
	end

	def refresh_stream
		if params[:project_id]
			@basecamp2_user = OauthUser.find_by(oauth_provider: 'basecamp2', organization_id: current_user.organization_id)
			if @basecamp2_user
				begin 
					events = BaseCampService.basecamp2_user_project_events(@basecamp2_user['oauth_access_token'], params[:basecamp_project_id], @basecamp2_user['oauth_instance_url'])
					arr1 = events
					arr2 = events
					if events
						events.each {|d| puts d['eventable']['id'] }
						h = Hash.new(0)
						events.each { |e| h[e['eventable']['id']] += 1 }
						puts "these are the eventable target ids: #{h}"
						# Activity.load_basecamp2_activities( e, params[:basecamp_project_id], current_user.id, params[:project_id] )
						arr1.each do |el1|
							mrg = []
							mrg << el1
							record = Activity.find_by(:backend_id => el1['eventable']['id'])
							unless record
								arr2.each do |el2|
									if el1['id'] != el2['id'] # This is ment to skip the identical object
										if el1['eventable']['id'] == el2['eventable']['id'] # We want to find the object that share the same eventable id
											mrg << el2
										end
									end
								end # <-----Ends arr2 Loop

								if !mrg.nil?
									Activity.load_basecamp2_activities( mrg, params[:basecamp_project_id], current_user.id, params[:project_id] )
								# else # if nothing was merged then save the single object
								end
							end # ends unless record
						end # <-------Ends arr1 Loop
					end # If event is valid
				rescue
					flash[:error] = "Error"
				else
					flash[:notice] = "Activities Sync"
				end
			end # If @Basecamp_user
		end
		respond_to do |format|
      		format.html { redirect_to settings_basecamp_path }
    end
	end

	def disconnect
		basecamp_user = OauthUser.find_by(id: params[:id])
		# destroy all integrations and activities;
		if basecamp_user
			basecamp_user.destroy
		end
		redirect_to settings_basecamp_path
	end


end
