class SalesforceController < ApplicationController
	layout "empty", only: [:index]
  def index
  	@projects = []
  	@activities_by_month = []

  	if params[:id].nil?

  		# account_id = '939a14b2-eb42-4201-bcd1-3c32552bc900'
  		# account_id = 'e699af1c-2069-44e0-9a2c-80b01cd0fab0'
  		return
  	else
  		# set this salesforce id to contextsmith account id
  		@salesforce_id = params[:id]
  		account_id = 'e699af1c-2069-44e0-9a2c-80b01cd0fab0'
  	  # account_id = 'fcd55ca2-0627-4097-8e00-29a5b8ca4b8f'
  	end

  	# check if id is valid and in the scope

  	# for now, just use test account

  	@projects = Project.includes(:activities).where(account_id: account_id)

    activities = []   
    if !@projects.empty?
    	if !params[:pid].nil?
    		@projects.each do |p|
    			if p.id == params[:pid]
    				activities = p.activities.includes(:comments, :user)
    				@pid = params[:pid]
    				break
    			end
    		end
  		else
  	  	activities = @projects[0].activities.includes(:comments, :user)
  	  	@pid = @projects[0].id
  		end
	    @activities_by_month = activities.select {|a| a.is_visible_to(current_user) }.group_by {|a| a.last_sent_date.strftime('%^B %Y') }
 		end
  end
end
