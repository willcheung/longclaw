require_dependency "app/services/basecamp_service.rb"
require 'oauth2'
require 'Time'

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

	def refresh_accounts
		@streams = Project.visible_to_admin(current_user.organization_id).is_active.includes(:salesforce_opportunity) # all active projects because "admin" role can see everything
	end

	def refresh_stream
		if params[:project_id]

			@basecamp2_user = OauthUser.find_by(oauth_provider: 'basecamp2', organization_id: current_user.organization_id)
			if @basecamp2_user
				begin 
					events = BaseCampService.basecamp2_user_project_events(@basecamp2_user, params[:basecamp_project_id])					
					object_info = events
					eventable_id_list = events
					list = []

					object_info.each do |y|
						creator_info = BaseCampService.basecamp2_user_info(y['creator']['id'],@basecamp2_user['oauth_access_token'],@basecamp2_user['oauth_instance_url'] )
						y.merge!(creator_info)
					end

					eventable_id_list.each{ |x| list << x['eventable']['id'] }
					list.uniq!
					if list
						list.each do |a|
							result = object_info.select { |b| b['eventable']['id'] == a }
							# Want to save into from
							# from = Hash.new { |h,k| h[k] = [] }
							# result.each do |c|
							# 		contact = Hash.new
							# 		contact["address"] = c['email_address']
							# 		contact["personal"] = c['name']
							# 		contact["avatar_url"] = c['avatar_url']
							# 		from["from"] << contact
							# end
							result.sort_by { |hash| hash['updated_at'].to_i }
							record = Activity.find_by(:backend_id => a)

							if record.nil?
								Activity.load_basecamp2_activities( result , params[:basecamp_project_id], current_user.id, params[:project_id] )
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

	def self.refresh(token)
		BaseCampServices.refresh_token(token)
	end



end
