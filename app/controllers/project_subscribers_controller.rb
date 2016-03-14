class ProjectSubscribersController < ApplicationController
	before_action :set_project_subscriber, only: [:destroy]

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