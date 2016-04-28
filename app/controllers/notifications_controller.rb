class NotificationsController < ApplicationController
  include Utils
  include ActionView::Helpers::TextHelper
  before_action :set_notification, only: [:update]
  before_action :set_visible_project_user, only: [:index, :show, :create]
  def index

    @notifications = []

    projects = Project.visible_to(current_user.organization_id, current_user.id).group("accounts.id").includes(:notifications)

    if !projects.empty?
      projects.each do |p| 
        p.notifications.each do |n|
          if(n.is_complete==false)
            if(n.sent_date.nil? || n.sent_date > Date.today-7.days)
              @notifications.push n
            end
          end
        end
      end
    end
  end

  def show_email_body
    result = get_email_and_member
    body = ""
    if !result.nil?
      body = '<b>'+result[0] + '</b>'+result[1]+'<hr>' + result[2]
    end
    render :text => simple_format(body, class: 'tooltip-inner-content')
  end

  def new
    @notification = Notification.new
  end


  def create
    o_due_date = nil
    r_date = nil
    if !params[:notification]["original_due_date"].blank?
      o_due_date = params[:notification]["original_due_date"].to_time.utc
      r_date = params[:notification]["original_due_date"].to_time.yesterday.utc
    end
    
    @notification = Notification.new(notification_params.merge(category: 'To-do',
      original_due_date: o_due_date,
      remind_date: r_date,
      has_time: false
      ))
 
    respond_to do |format|
      if @notification.save
        format.html { redirect_to @notification, notice: 'Notification was successfully created.' }
        format.js 
        #format.json { render action: 'show', status: :created, location: @project }
      else
        format.html { render action: 'new' }
        format.js { render json: @notification.errors, status: :unprocessable_entity }
        #format.json { render json: @project.errors, status: :unprocessable_entity }
      end
    end
  end

  def update
    new_params = notification_params
    if notification_params[:original_due_date].blank?
      new_params = notification_params.merge(remind_date: nil)
    else
      new_params = notification_params.merge(
                          remind_date: notification_params[:original_due_date].to_time.yesterday.utc,
                          original_due_date: notification_params[:original_due_date].to_time.utc)
    end

    respond_to do |format|
      if @notification.update(new_params)
        format.html { redirect_to @notification, notice: 'Notification was successfully updated.' }
        format.json { head :no_content }
        format.js { render action: 'index', status: :created, location: @notification }
      else
        format.html { render action: 'index' }
        format.json { render json: @notification.errors, status: :unprocessable_entity }
        format.js { render json: @notification.errors, status: :unprocessable_entity }
      end
    end  
  end

  def show_member_by_org
    query = <<-SQL
      SELECT user_id FROM project_members where project_id=('#{params[:id]}') and not user_id is NULL
    SQL

    members= ProjectMember.find_by_sql(query)

    result = ""
    members.each do |m|
      user = User.find_by_id(m.user_id)
      result = result + "<option value='#{m.user_id}'>#{user.first_name} #{user.last_name} '#{user.email}'</option>"
    end

    render :text=>result
    

  end


  def update_is_complete
    target = Notification.find_by_id(params[:id])

    if(target.is_complete)
      target.update(is_complete: false, completed_by: nil, complete_date: nil)
    else
      target.update(is_complete: true, completed_by: current_user.id, complete_date: Time.now.utc)
    end
    
    respond_to :js

  end

	def sasuke
   is_test = true

   Organization.all.each do |org|
      org.accounts.each do |acc| 
        acc.projects.each do |proj|
          # puts "Loading project...\nOrg: " + org.name + ", Account: " + acc.name + ", Project " + proj.name
          ContextsmithService.load_emails_from_backend(proj, nil, 300, nil, true, true, is_test)
          sleep(1)
        end
      end
    end

     # proj = Project.find_by_id("f460b2a2-29f5-4798-a239-b71955c2b96a")
     # ContextsmithService.load_emails_from_backend(proj, nil, 300, nil, true, true, is_test)

    @notification = Notification.first
   
    render :show
	end

  

  private
  # Use callbacks to share common setup or constraints between actions.
  def set_notification
    @notification = Notification.find(params[:id])
  end

  # Never trust parameters from the scary internet, only allow the white list through.
  def notification_params
    params.require(:notification).permit(:description, :name, :original_due_date, :remind_date, :assign_to, :project_id, :category)
  end

  def set_visible_project_user
    @projects = Project.joins(:account)
                      .where('accounts.organization_id = ? 
                              AND (projects.is_public=true 
                                    OR (projects.is_public=false AND projects.owner_id = ?))', current_user.organization_id, current_user.id)
           

    @projects_reverse = @projects.map { |p| [p.id, p.name] }.to_h

    @users = current_user.organization.users.map { |u| [u.first_name+' '+ u.last_name+' '+u.email, u.id] }.to_h
    @users_reverse = current_user.organization.users.map { |u| [u.id,u.first_name+' '+ u.last_name] }.to_h
   
  end

  def get_email_and_member
    @notification = Notification.find_by_id(params[:id])

    if(params[:conversation_id].nil? || params[:message_id].nil? || params[:project_id].nil?)
      return nil
    end

    if(params[:conversation_id].empty? || params[:message_id].empty? || params[:project_id].empty?)
      return nil
    end

    query = <<-SQL
      SELECT messages->>'content' as content,
             messages->'from' as from, 
             messages -> 'to' as to,
             messages -> 'cc' as cc
      FROM activities, LATERAL jsonb_array_elements(email_messages) messages
      where backend_id='#{params[:conversation_id]}' and messages ->>'messageId' = '#{params[:message_id]}' and project_id = '#{params[:project_id]}'
      GROUP BY 1,2,3,4;
    SQL

    result= Activity.find_by_sql(query)

    if(result.nil?)
      return nil
    end

    email = JSON.parse(result[0].content)
    body = email['body']

    total = result[0].to.size + result[0].cc.size

    member = ' to '

    counter = 0
    result[0].to.each do |t|
      if counter>=4
        break
      end
      member = member + get_first_name(t['personal']) + ', '
      counter = counter + 1
    end

    result[0].cc.each do |c|
      if counter>=4
        break
      end
      member = member + get_first_name(c['personal']) + ', '
      counter = counter + 1
    end

    member.slice!(member.length-2, member.length)

    if counter < total
      member = member + ' and ' + (total-counter).to_s + ' others'
    end


    final_result = Array.new(3)
    final_result[0] = result[0].from[0]['personal']
    final_result[1] = member
    final_result[2] = body

    return final_result
  end

  def show
    result = get_email_and_member
    @body = ""
    if !result.nil?
      @body = '<b>'+result[0] + '</b>'+result[1]+'<hr>' + result[2]
    end
  end
end
