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
            @final_filter_user = Activity.all_involved_user(p, current_user)
            activities = Activity.get_activity_by_filter(p, params)
            @project_risk_score =p.current_risk_score(current_user)
            @project = p
    				break
    			end
    		end
  		else
        @final_filter_user = Activity.all_involved_user(@projects[0], current_user)
        activities = Activity.get_activity_by_filter(@projects[0], params)
        
        @project_risk_score = @projects[0].current_risk_score(current_user)
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
      @project_open_risks_count = @project.notifications.where(is_complete: false, category: Notification::CATEGORY[:Risk]).length
      @notifications = @project.notifications.order(:is_complete, :original_due_date)  

      @pinned_activities = @project.activities.pinned.includes(:comments)
      # filter out not visible items
      @pinned_activities = @pinned_activities.select {|a| a.is_visible_to(current_user) }

      @data = @project.activities.where(category: %w(Conversation Meeting))

      @project_open_tasks_count = @project.notifications.where(is_complete: false).length
      @project_pinned_count = @project.activities.pinned.length

      @users_reverse = current_user.organization.users.order(:first_name).map { |u| [u.id,u.first_name+' '+ u.last_name] }.to_h 
 		end

    if(!params[:category].nil? and !params[:category].empty?)
      @category_param = params[:category].split(',')
    end

    if(!params[:emails].nil? and !params[:emails].empty?)
      @filter_email = params[:emails].split(',')
    end
  end

  def link_salesforce_account
    #check if contextsmith account is connected
    if !params[:account_id].nil?
      salesforce_account_duplicate = SalesforceAccount.where(contextsmith_account_id: params[:account_id])

      salesforce_account_duplicate.each do |s|
        s.contextsmith_account_id = nil
        s.save
      end
    end

    salesforce_account = SalesforceAccount.find_by(id: params[:salesforce_id], contextsmith_organization_id: current_user.organization_id)
    if !salesforce_account.nil?
      salesforce_account.contextsmith_account_id = params[:account_id]
      salesforce_account.save
    end

    account = Account.find_by(id: params[:account_id])
    if !account.nil?
      account.salesforce_id = params[:salesforce_id]
      account.save
    end
    
    respond_to do |format|
      format.html { redirect_to settings_salesforce_path }
    end
  end

  def refresh
    SalesforceAccount.load(current_user)

    render :text => ' '
         
  end

  def remove_link
    salesforce_account = SalesforceAccount.eager_load(:account).find_by(id: params[:id], contextsmith_organization_id: current_user.organization_id)

    if !salesforce_account.nil?
      if !salesforce_account.account.nil? 
        salesforce_account.account.salesforce_id = ''
      end
      salesforce_account.contextsmith_account_id = nil
      salesforce_account.save
    end

    respond_to do |format|
      format.html { redirect_to settings_salesforce_path }
    end

  end


  def disconnect
    # update account
    # delete salesforce data
    # delete salesforce oauth_user
    Account.where(organization_id: current_user.organization_id).update_all(salesforce_id: '')
    SalesforceAccount.where(contextsmith_organization_id: current_user.organization_id).delete_all
    salesforce_user = OauthUser.find_by(id: params[:id])
    salesforce_user.destroy

    respond_to do |format|
      format.html { redirect_to settings_salesforce_path }
    end
  end
end
