class SalesforceController < ApplicationController
	layout "empty", only: [:index]
  
  def index
    @category_param = []
    @filter_email = []

  	@projects = []
  	@activities_by_month = []
    @activities_by_date = []
    @project = Project.new
    @isconnect = false

    @actiontype = 'show'
    @pinned_activities = []
    @data = []

  	if params[:id].nil?
  		return
  	else
  		# set this salesforce id to contextsmith account id
  		@salesforce_id = params[:id]

      salesforce = SalesforceAccount.eager_load(:account).find_by(salesforce_account_id: params[:id], contextsmith_organization_id: current_user.organization_id)

      if salesforce.nil?
        return
      end

      account = salesforce.account
      if account.nil?
        return
      end
  	end

    if !params[:actiontype].nil?
      @actiontype = params[:actiontype]
    end

    @isconnect = true

  	# check if id is valid and in the scope

  	# for now, just use test account
  	@projects = Project.includes(:activities).where(account_id: account.id)
    activities = []   
    if !@projects.empty?
    	if !params[:pid].nil?
    		@projects.each do |p|
    			if p.id == params[:pid]
            @final_filter_user = p.all_involved_people(current_user.email)
            activities = Activity.get_activity_by_filter(p, params)
            @project_risk_score = p.current_risk_score(current_user.time_zone)
            @project = p
    				break
    			end
    		end
  		else
        @final_filter_user = @projects[0].all_involved_people(current_user.email)
        activities = Activity.get_activity_by_filter(@projects[0], params)
        
        @project_risk_score = @projects[0].current_risk_score(current_user.time_zone)
        @project = @projects[0]
  		end
	    @activities_by_month = activities.select {|a| a.is_visible_to(current_user) }.group_by {|a| a.last_sent_date.strftime('%^B %Y') }
      activities_by_date_temp = activities.select {|a| a.is_visible_to(current_user) }.group_by {|a| a.last_sent_date.strftime('%Y %m %d') }

      activities_by_date_temp.each do |date, activities|
        temp = Struct.new(:utc_milli_timestamp, :count).new
        temp.utc_milli_timestamp = DateTime.strptime(date, '%Y %m %d').to_i * 1000
        temp.count = activities.length
        @activities_by_date.push(temp)
      end
      @activities_by_date = @activities_by_date.sort {|x, y| y.utc_milli_timestamp <=> x.utc_milli_timestamp }.reverse!

      @project_last_activity_date = @project.activities.where(category: "Conversation").maximum("activities.last_sent_date")
      project_last_touch = @project.activities.find_by(category: "Conversation", last_sent_date: @project_last_activity_date)
      @project_last_touch_by = project_last_touch ? project_last_touch.from[0].personal : "--"
      @project_open_risks_count = @project.notifications.open.risks.count
      @notifications = @project.notifications.order(:is_complete, :original_due_date)  

      @pinned_activities = @project.activities.pinned.includes(:comments)
      # filter out not visible items
      @pinned_activities = @pinned_activities.select {|a| a.is_visible_to(current_user) }

      @data = @project.activities.where(category: %w(Conversation Meeting))

      @project_open_tasks_count = @project.notifications.open.count
      @project_pinned_count = @project.activities.pinned.count

      @users_reverse = get_current_org_users
 		end

    if(!params[:category].nil? and !params[:category].empty?)
      @category_param = params[:category].split(',')
    end

    if(!params[:emails].nil? and !params[:emails].empty?)
      @filter_email = params[:emails].split(',')
    end
  end

  def link_salesforce_account
    # One CS Account can link to many Salesforce Accounts
    salesforce_account = SalesforceAccount.find_by(id: params[:salesforce_id], contextsmith_organization_id: current_user.organization_id)
    if !salesforce_account.nil?
      salesforce_account.account = Account.find_by_id(params[:account_id])
      salesforce_account.save
    end
    
    respond_to do |format|
      format.html { redirect_to settings_salesforce_path }
    end
  end

  def refresh_accounts
    SalesforceAccount.load(current_user.organization_id)
    render :text => ' '   
  end

  def refresh_opportunities
    SalesforceOpportunity.load(current_user.organization_id)
    render :text => ' '
  end

  def refresh_activities
    @streams = Project.all.is_active.includes(:salesforce_opportunities) # all active projects because "admin" role can see everything
    
    @streams.each do |s|
      if s.salesforce_opportunities.empty? # Stream not linked to SF Opportunity
        if !s.account.salesforce_accounts.empty? # Stream linked to SF Account
          s.account.salesforce_accounts.each do |sf_a|
            Activity.load_salesforce_activities(s, current_user.organization_id, sf_a.salesforce_account_name)
          end
        end
      else # Stream linked to Opportunity

      end
    end

    render :text => ' '
  end

  def remove_account_link
    salesforce_account = SalesforceAccount.eager_load(:account).find_by(id: params[:id], contextsmith_organization_id: current_user.organization_id)

    if !salesforce_account.nil?
      salesforce_account.salesforce_opportunities.destroy_all
      salesforce_account.contextsmith_account_id = nil
      salesforce_account.save
    end

    respond_to do |format|
      format.html { redirect_to settings_salesforce_path }
    end

  end


  def disconnect
    # delete salesforce data
    # delete salesforce oauth_user
    SalesforceAccount.where(contextsmith_organization_id: current_user.organization_id).destroy_all
    salesforce_user = OauthUser.find_by(id: params[:id])
    salesforce_user.destroy

    respond_to do |format|
      format.html { redirect_to settings_salesforce_path }
    end
  end
end
