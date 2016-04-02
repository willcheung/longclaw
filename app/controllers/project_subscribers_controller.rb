class ProjectSubscribersController < ApplicationController
	before_action :set_project_subscriber, only: [:destroy]

	def create
    @single = true
    if (params[:user_id].include? ",")
      user_ids = params[:user_id].split(", ")
      @single = false
    end
		@subscriber = ProjectSubscriber.new(user_id: params[:user_id], project_id: params[:project_id])
    puts @subscriber
		@project = Project.find(params[:project_id])
    puts @project

    respond_to do |format|
      if @subscriber.save
      	format.js 
        format.json { head :no_content }
        format.html { redirect_to :back }
      else
        format.json { render json: @subscriber.errors, status: :unprocessable_entity }
      end
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

	private
  
	def set_project_subscriber
    @project_subscriber = ProjectSubscriber.where("user_id = ? and project_id = ?", params[:user_id], params[:project_id])
  end
end