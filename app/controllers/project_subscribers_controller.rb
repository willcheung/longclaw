class ProjectSubscribersController < ApplicationController
	before_action :set_project_subscriber, only: [:destroy]

  # for subscribing yourself to a project
	def create
		@subscriber = ProjectSubscriber.new(user_id: params[:user_id], project_id: params[:project_id])
		@project = Project.find(params[:project_id])

    respond_to do |format|
      if @subscriber.save
      	format.js 
        format.json { head :no_content }
      else
        format.json { render json: @subscriber.errors, status: :unprocessable_entity }
      end
    end
	end

  # for subscribing multiple internal users
  def create_all
    return @project_subscribers = [] if (params[:user_id].empty?)
    # @project_subscribers is array of user_id
    if (params[:user_id].include? ",")
      @project_subscribers = params[:user_id].split(",")
    else
      @project_subscribers = [params[:user_id]]
    end
    # check if user subscribed herself
    @self_subscribe = @project_subscribers.include? current_user.id
    # @project_subscribers is array of subscribers
    @project_subscribers.map! { |s| ProjectSubscriber.new(user_id: s, project_id: params[:project_id]) }
    # @project_subscribers is array of subscribers who are saved successfully
    @project_subscribers.select! { |s| s.save }
    @project = Project.find(params[:project_id])

    respond_to do |format|
      format.html { redirect_to :back }
      format.json { head :no_content }
      format.js
    end
  end

	def destroy
		@project = Project.find(params[:project_id])
		@project_subscriber.destroy_all
    respond_to do |format|
      format.js 
      format.json { head :no_content }
    end
	end

  def destroy_other
    @project_subscriber = ProjectSubscriber.find(params[:id])
    @self_unsubscribe = @project_subscriber.user_id == current_user.id
    @project = @project_subscriber.project
    @project_subscriber.destroy
    respond_to do |format|
      format.html { redirect_to :back }
      format.js
    end
  end

	private
  
	def set_project_subscriber
    @project_subscriber = ProjectSubscriber.where("user_id = ? and project_id = ?", params[:user_id], params[:project_id])
  end
end