class NotificationsController < ApplicationController
  include Utils
  include ActionView::Helpers::TextHelper
  before_action :set_notification, only: [:update]
  before_action :set_visible_project_user, only: [:index, :show, :create]
  def index
    
    # only show valid notifications (both project and activities must be visible to user)
    # for now will only show incomplete tasks
    @notifications = []

    @complete = "incomplete"
 
    filter_statement = Array.new
    if !params[:type].nil?
      if params["type"]=="complete"
        filter_statement.push(" is_complete=true ")
        @complete = "complete"
      elsif params["type"]=="incomplete"
        filter_statement.push(" is_complete=false ")
        @complete = "incomplete"
      elsif params["type"]=="all"  
        # must put something in the where clause, so put TRUE
        filter_statement.push(" TRUE ")
        @complete = "all"
      end
    end 

    @assignee = ""
    if !params[:assignee].nil?
      if params["assignee"]=="me"
        filter_statement.push(" assign_to='#{current_user.id}' ");
        @assignee = "me"
      elsif params["assignee"]=="none"
        filter_statement.push(" assign_to is NULL ")
        @assignee = "none"
      end
    end 

    @duedate = ""
    if !params[:duedate].nil?
      if params["duedate"]=="oneweek"
        local_current_time = Time.zone.at(Time.now.utc)
        start_utc_time = Time.new(local_current_time.year, local_current_time.month, local_current_time.day).utc.strftime("%Y-%m-%d %H:%M:%S")
        local_end_time = local_current_time + 7.day
        end_utc_time = Time.new(local_end_time.year, local_end_time.month, local_end_time.day,23,59,59).utc.strftime("%Y-%m-%d %H:%M:%S")

        # filter_statement.push(" original_due_date BETWEEN CURRENT_TIMESTAMP + INTERVAL '1 week' and CURRENT_TIMESTAMP ")
        filter_statement.push(" (original_due_date BETWEEN '"+start_utc_time.to_s+"' AND '"+end_utc_time.to_s + "') ")
        @duedate = "oneweek"
      elsif params["duedate"]=="none"
        filter_statement.push(" original_due_date is NULL ")
        @duedate = "none"
      elsif params["duedate"]=="overdue"
        local_current_time = Time.zone.at(Time.now.utc)
        end_utc_time = Time.new(local_current_time.year, local_current_time.month, local_current_time.day,0,0,0).utc.strftime("%Y-%m-%d %H:%M:%S")
        filter_statement.push(" (original_due_date < '"+ end_utc_time.to_s + "') ")
        @duedate = "overdue"
      end
    end 

    final_filter = filter_statement.join(" AND ")

    @projects = Project.visible_to(current_user.organization_id, current_user.id).order(:name)

    if @projects.empty?
      #no project, no notifications
      return
    end

    @select_project = 0
    # always check if projectid is in visible projects in case someone do evil
    if !params[:projectid].nil? and !@projects.nil? and @projects.map(&:id).include? params[:projectid]
      newProject = Array.new(1)
      newProject[0] = params[:projectid]
      total_notifications = Notification.find_project_and_user(newProject, final_filter)
      @select_project = params[:projectid]
    else
      total_notifications = Notification.find_project_and_user(@projects.map(&:id), final_filter)
    end

    #show every risk, smart action, opportunity regardless of private conversation
    @notifications = total_notifications

  end

  def show_email_body
    result = get_email_and_member
    body = ""
    if !result.nil?
      sent_time = Time.zone.at(result[3]).strftime('%b %e').to_s
      body = '<b>'+result[0] + '</b>'+result[1]+'<br><font color="gray">'+sent_time+'</font><hr>' + simple_format(result[2], class: 'tooltip-inner-content')
    else
      body = 'Email not found!'
    end
    render :text => body
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

    # send notification email for the assign_to user
    send_email = @notification.assign_to.present? && @notification.assign_to != current_user.id
 
    respond_to do |format|
      if @notification.save
        UserMailer.task_assigned_notification_email(@notification, current_user).deliver_later if send_email
        format.html { redirect_to :back, notice: 'To-Do was successfully created.' }
        format.js 
        #format.json { render action: 'show', status: :created, location: @project }
      else
        format.html { redirect_to :back, notice: 'To-Do was not created. Did you assign it to a project?' }
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
                          remind_date: DateTime.strptime(notification_params[:original_due_date], '%m/%d/%Y').to_date.yesterday,
                          original_due_date: DateTime.strptime(notification_params[:original_due_date], '%m/%d/%Y').to_date)
    end

    # send notification email for the new assign_to user
    send_email = notification_params[:assign_to].present? && notification_params[:assign_to] != @notification.assign_to && notification_params[:assign_to] != current_user.id

    respond_to do |format|
      if @notification.update(new_params)
        UserMailer.task_assigned_notification_email(@notification, current_user).deliver_later if send_email
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
          ContextsmithService.load_emails_from_backend(proj, nil, 300, nil, true, true, is_test,0)
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
                                    OR (projects.is_public=false AND projects.owner_id = ?))', current_user.organization_id, current_user.id).order("lower(projects.name)")
           

    @projects_reverse = @projects.map { |p| [p.id, p.name] }.to_h

    @users = current_user.organization.users.map { |u| [u.first_name+' '+ u.last_name+' '+u.email, u.id] }.to_h
    @users_reverse = current_user.organization.users.order(:first_name).map { |u| [u.id,u.first_name+' '+ u.last_name] }.to_h
  end

  def get_email_and_member
    @notification = Notification.find_by_id(params[:id])

    if(@notification.nil?)
      return nil
    end

    # Opportunity only have project_id and conversation_id
    # Smart action and risk should have conversation_id, message_id and project_id

    if(@notification.category!=Notification::CATEGORY[:Action] and @notification.category!=Notification::CATEGORY[:Opportunity] and @notification.category!=Notification::CATEGORY[:Risk] )
      return nil
    end

    if @notification.category==Notification::CATEGORY[:Action] or @notification.category==Notification::CATEGORY[:Risk]
      query = <<-SQL
        SELECT messages->>'content' as content,
               messages->'from' as from, 
               messages -> 'to' as to,
               messages -> 'cc' as cc,
               messages ->> 'sentDate' as sentdate
        FROM activities, LATERAL jsonb_array_elements(email_messages) messages
        WHERE backend_id='#{@notification.conversation_id}' and messages ->>'messageId' = '#{@notification.message_id}' and project_id = '#{@notification.project_id}' 
        LIMIT 1
      SQL
    elsif @notification.category==Notification::CATEGORY[:Opportunity]
       query = <<-SQL
        SELECT messages->>'content' as content,
               messages->'from' as from, 
               messages -> 'to' as to,
               messages -> 'cc' as cc,
               messages ->> 'sentDate' as sentdate
        FROM activities, LATERAL jsonb_array_elements(email_messages) messages
        WHERE backend_id='#{@notification.conversation_id}' AND project_id = '#{@notification.project_id}' ORDER BY messages ->> 'sentDate' DESC 
        LIMIT 1
      SQL
    else
      return nil
    end

    result= Activity.find_by_sql(query)

    if(result.nil?)
      return nil
    end

    index = 0

    # patch, somehow on production this may return nil
    if(result[index].nil?)
      return nil
    end

    # Unfortunately we are storing JSON string in actitivities
    # so content can be nil because backend JSON format may change
    # (Actually anything can be nil, be careful)
    if(result[index].content.nil?)
      return nil
    end
    email = JSON.parse(result[index].content)
    body = email['body']
    if body.nil?
      return nil
    end
    sentdate = result[index].sentdate
    if(sentdate.nil?)
      return nil
    end

    total = 0
    if(result[index].to.nil? and result[index].cc.nil?)
      return nil
    elsif result[index].to.nil?
      total = result[index].cc.size
    elsif result[index].cc.nil?
      total = result[index].to.size
    else
      total = result[index].to.size + result[index].cc.size
    end

    if total==0
      return nil
    end

    member = ' to '

    counter = 0

    if !result[index].to.nil?
      result[index].to.each do |t|
        if counter>=4
          break
        end
        member = member + get_first_name(t['personal']) + ', '
        counter = counter + 1
      end
    end


    if !result[index].cc.nil?
      result[index].cc.each do |c|
        if counter>=4
          break
        end
        member = member + get_first_name(c['personal']) + ', '
        counter = counter + 1
      end
    end

    member.slice!(member.length-2, member.length)

    if counter < total
      member = member + ' and ' + (total-counter).to_s + ' others'
    end

    final_result = Array.new(4)
    final_result[0] = result[index].from[0]['personal']
    final_result[1] = member

    #check if this notification is visible to current user
    if Activity.find_by(backend_id: @notification.conversation_id, project_id: @notification.project_id).is_visible_to(current_user) 
      final_result[2] = body
    else
      final_result[2] = 'This is private conversation'
    end

    final_result[3] = sentdate.to_i

    return final_result
  end

  def show
    result = get_email_and_member
    @body = ""
    if !result.nil?
      sent_time = Time.zone.at(result[3]).strftime('%b %e').to_s
      @body = '<b>'+result[0] + '</b>'+result[1]+'<br>'+sent_time+'<hr>' + result[2]
    end
  end
end
