class SearchController < ApplicationController

  def results
    respond_to do |format|
      if params[:project_id].empty?
        # respond with invalid message
        @error = "Please include a project in your search!"
        format.js { render 'error' }
      else
        @project = Project.visible_to(current_user.organization_id, current_user.id).find(params[:project_id])
        if params[:query].nil? || params[:query].empty?
          # respond with project page
          format.html { redirect_to @project }
        else
          # respond with search result page
      	  @activities = ContextsmithService.load_emails_from_backend(@project, 100, params[:query], false, nil, nil, nil, nil)
          format.html
        end
      end
    end
  end

  # Rolling our own autocomplete handler because of visible_to project scope
  def autocomplete_project_name
  	@projects = Project.visible_to(current_user.organization_id, current_user.id).where("lower(projects.name) like ?", "%#{params[:term]}%")
  	
  	respond_to do |format|
  		format.json { render json: @projects.map { |x| { :id => x.id, :name => x.name, :account => x.account.name } }.to_json.html_safe }
  	end
  end

  def autocomplete_project_subs
    if (params[:type] == "daily")
      subs = ProjectSubscriber.all.where(project_id: params[:project_id], daily: true).pluck(:user_id)
      print subs.length
    elsif (params[:type] == "weekly")
      subs = ProjectSubscriber.all.where(project_id: params[:project_id], weekly: true).pluck(:user_id)
    end
    @users = current_user.organization.users.where.not(id: subs)

    respond_to do |format|
      format.json { render json: @users.map { |x| { :id => x.id, :name => get_full_name(x), :email => x.email } }.to_json.html_safe }
    end
  end

  def autocomplete_project_member
    # current_user.organization.accounts.contacts + current_user.organization.users
    @search_list = []
   
    accounts_result = current_user.organization.accounts.includes(:contacts).each do |account|
      account.contacts.each do |contact|
        new_user = Struct.new(:first_name, :last_name, :email).new
        new_user.email = contact.email
        new_user.first_name = contact.first_name
        new_user.last_name = contact.last_name
        @search_list.push(new_user)
      end
    end

    current_user.organization.users.each do |user|
      new_user = Struct.new(:first_name, :last_name, :email).new
      new_user.email = user.email
      new_user.first_name = user.first_name
      new_user.last_name = user.last_name
      @search_list.push(new_user)
    end

    respond_to do |format|
      format.json { render json: @search_list.map { |x| { :name => x.first_name + ' ' + x.last_name, :email => x.email } }.to_json.html_safe }
    end
  end

  def autocomplete_salesforce_account_name
    @salesforce_accounts = SalesforceAccount.where("lower(salesforce_account_name) like ? AND contextsmith_organization_id=?", "%#{params[:term]}%", "#{current_user.organization_id}")
  
    respond_to do |format|
      format.json { render json: @salesforce_accounts.map { |x| { :id => x.id, :name => x.salesforce_account_name } }.to_json.html_safe }
    end
  end

end