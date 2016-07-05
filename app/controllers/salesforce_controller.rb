class SalesforceController < ApplicationController
	layout "empty", only: [:index]
  def index
  	@projects = []
  	@activities_by_month = []
    @project = Project.new
    @isconnect = true

  	if params[:id].nil?
  		return
  	else
  		# set this salesforce id to contextsmith account id
  		@salesforce_id = params[:id]
      account = Account.find_by(salesforce_id: params[:id])
      if account.nil?
        @isconnect = false
        return
      end
  	end

  	# check if id is valid and in the scope

  	# for now, just use test account

  	@projects = Project.includes(:activities).where(account_id: account.id)
    activities = []   
    if !@projects.empty?
    	if !params[:pid].nil?
    		@projects.each do |p|
    			if p.id == params[:pid]
    				activities = p.activities.includes(:comments, :user)
            @project_risk_score =p.current_risk_score
            @project = p
    				break
    			end
    		end
  		else
  	  	activities = @projects[0].activities.includes(:comments, :user)
        @project_risk_score = @projects[0].current_risk_score
        @project = @projects[0]
  		end
	    @activities_by_month = activities.select {|a| a.is_visible_to(current_user) }.group_by {|a| a.last_sent_date.strftime('%^B %Y') }
      @project_last_activity_date = @project.activities.where(category: "Conversation").maximum("activities.last_sent_date")
      project_last_touch = @project.activities.find_by(category: "Conversation", last_sent_date: @project_last_activity_date)
      @project_last_touch_by = project_last_touch ? project_last_touch.from[0].personal : "--"

 		end
  end


  def disconnect
    salesforce_user = OauthUser.find_by(oauth_instance_url: ENV['salesforce_url_instance'], organization_id: current_user.organization_id)
    salesforce_user.destroy

    respond_to do |format|
      format.html { redirect_to settings_url }
    end
  end
end
