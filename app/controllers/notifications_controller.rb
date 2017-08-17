class NotificationsController < ApplicationController
  include ActionController::Live

  before_action :set_notification, only: [:update, :update_is_complete, :download_attachment]
  before_action :set_visible_project_user, only: [:index, :show, :create]
  before_action :get_current_org_users, only: [:index, :show, :create, :create_from_suggestion]

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
  end
end
