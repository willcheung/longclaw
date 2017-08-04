class NotificationsController < ApplicationController
  ### TODO: refactor show_email_body so that it does not depend on simple_format which must be included from ActionView module (separate Controller from Views)
  include ActionView::Helpers::TextHelper
  include ActionController::Live

  before_action :set_notification, only: [:update, :update_is_complete, :show_email_body, :download_attachment]
  before_action :set_visible_project_user, only: [:index, :show, :create]

  def download_attachment
    render plain: 'You don\'t have access to this file' and return unless @notification.is_visible_to(current_user)

    description = JSON.parse(@notification.description)
    urn = description[:urn]
    user_email = urn.split(':').fourth
    att_user = current_user.organization.users.find_by_email(user_email)
    render plain: 'You don\'t have access to this file' and return unless att_user

    # base_url = ENV["csback_base_url"] + "/newsfeed/download"

    render plain: 'OK'
  end

  def index
    return if @projects.empty? # no project, no notifications

    # only show valid notifications (both project and activities must be visible to user)
    # for now will only show incomplete tasks
    @notifications = Notification.non_attachments

    if params[:type].present?
      @complete = params[:type]
      if params[:type] == "incomplete"
        @notifications = @notifications.open
      elsif params[:type] == "complete"
        @notifications = @notifications.where(is_complete: true)
      end
    end

    if params[:assignee].present?
      @assignee = params[:assignee]
      if params[:assignee] == "me"
        @notifications = @notifications.where(assign_to_user: current_user)
      elsif params[:assignee] == "none"
        @notifications = @notifications.where(assign_to: nil)
      end
    end

    if params[:duedate].present?
      @duedate = params[:duedate]
      if params["duedate"] == "oneweek"
        @notifications = @notifications.where(original_due_date: Time.current.midnight.utc...7.days.from_now.end_of_day.utc)
      elsif params["duedate"]=="none"
        @notifications = @notifications.where(original_due_date: nil)
      elsif params["duedate"]=="overdue"
        @notifications = @notifications.where(original_due_date: Time.at(0).utc...Time.current.utc)
      end
    end

    # always check if projectid is in visible projects in case someone do evil
    if params[:projectid].present? && @projects.ids.include?(params[:projectid])
      @select_project = params[:projectid]
      @notifications = @notifications.where(project_id: params[:projectid])
    else
      @notifications = @notifications.where(project_id: @projects.ids)
    end
  end

  # TODO: move view logic (like simple_format part) into its own partial or template
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
    if params[:notification]["original_due_date"].present?
      o_due_date = params[:notification]["original_due_date"].to_time.utc
      r_date = params[:notification]["original_due_date"].to_time.yesterday.utc
    end

    @notification = Notification.new(notification_params.merge(
      category: Notification::CATEGORY[:Todo],
      original_due_date: o_due_date,
      remind_date: r_date,
      has_time: false,
      assign_to: current_user.id
    ))

    # send notification e-mail for the assign_to user
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

  def create_from_suggestion
    @notification = Notification.new(notification_params.merge(
      category: Notification::CATEGORY[:Todo],
      has_time: true
    ))

    @users_reverse = get_current_org_users

    # send notification e-mail for the assign_to user
    send_email = @notification.assign_to.present? && @notification.assign_to != current_user.id

    respond_to do |format|
      if @notification.save
        UserMailer.task_assigned_notification_email(@notification, current_user).deliver_later if send_email
        format.html { redirect_to :back, notice: 'To-Do was successfully created.' }
        format.js
      else
        format.html { redirect_to :back, notice: 'To-Do was not created. Did you assign it to a project?' }
        format.js { render json: @notification.errors, status: :unprocessable_entity }
      end
    end
  end

  def update
    new_params = notification_params
    if notification_params[:original_due_date].blank?
      new_params = notification_params.merge(remind_date: nil)
    else
      if notification_params[:original_due_date].include?("-")
        due_date = DateTime.strptime(notification_params[:original_due_date], '%Y-%m-%d')
      else
        due_date = DateTime.strptime(notification_params[:original_due_date], '%m/%d/%Y')
      end

      new_params = notification_params.merge(
                          remind_date: due_date.to_date.yesterday,
                          original_due_date: due_date.to_date)
    end

    # send notification e-mail for the new assign_to user
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

  def update_is_complete
    if @notification.is_complete
      @notification.update(is_complete: false, completed_by: nil, complete_date: nil)
    else
      @notification.update(is_complete: true, completed_by: current_user.id, complete_date: Time.now.utc)
    end
    respond_to :js
  end

  private
  # Use callbacks to share common setup or constraints between actions.
  def set_notification
    @notification = Notification.find(params[:id])
  end

  # Never trust parameters from the scary internet, only allow the white list through.
  def notification_params
    params.require(:notification).permit(:description, :name, :original_due_date, :remind_date, :assign_to, :project_id, :category, :message_id, :conversation_id, :activity_id)
  end

  def set_visible_project_user
    @projects = Project.visible_to(current_user.organization_id, current_user.id)

    @projects_reverse = @projects.map { |p| [p.id, p.name] }.to_h

    @users = current_user.organization.users.map { |u| [u.first_name+' '+ u.last_name+' '+u.email, u.id] }.to_h
    @users_reverse = get_current_org_users
  end

  def get_email_and_member
    return nil if(@notification.nil?)

    # Opportunity only have project_id and conversation_id
    # Smart action and risk should have conversation_id, message_id and project_id

    if(@notification.category!=Notification::CATEGORY[:Action] and @notification.category!=Notification::CATEGORY[:Opportunity] and @notification.category!=Notification::CATEGORY[:Alert] )
      return nil
    end

    if @notification.category==Notification::CATEGORY[:Action] or @notification.category==Notification::CATEGORY[:Alert]
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
