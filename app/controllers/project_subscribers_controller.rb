class ProjectSubscribersController < ApplicationController
  before_action :set_project, except: [:destroy_other]
	before_action :set_project_subscriber, only: [:create, :destroy]

  # for subscribing yourself to a project
	def create
    puts '================'
    if params[:type] == "daily"
      if @project_subscriber
        puts 'daily - found'
        @project_subscriber.daily = true
      else
        puts 'daily - nil'
        @project_subscriber = ProjectSubscriber.new(user_id: params[:user_id], project_id: params[:project_id], weekly: false)
      end
    elsif params[:type] == "weekly"
      if @project_subscriber
        puts 'weekly - found'
        @project_subscriber.weekly = true
      else
        puts 'weekly - nil'
        @project_subscriber = ProjectSubscriber.new(user_id: params[:user_id], project_id: params[:project_id], daily: false)
      end
    end
    puts '=============='

    respond_to do |format|
      if @project_subscriber.save
      	format.js 
        format.json { head :no_content }
      else
        format.json { render json: @project_subscriber.errors, status: :unprocessable_entity }
      end
    end
	end

  # for subscribing multiple internal users
  def create_all
    return @project_subscribers = [] if (params[:user_id].empty?)
    # @project_subscribers is array of user_id's
    if (params[:user_id].include? ",")
      @project_subscribers = params[:user_id].split(",")
    else
      @project_subscribers = [params[:user_id]]
    end
    # check if user subscribed herself
    @self_subscribe = @project_subscribers.include? current_user.id
    # @project_subscribers is array of subscribers
    @project_subscribers.map! do |s|
      _ps = ProjectSubscriber.find_by(user_id: s, project_id: params[:project_id]) 
      if _ps
        if params[:type] == "daily" and not _ps.daily
          _ps.daily = true
          _ps  # only return a sub when there's an update
        elsif params[:type] == "weekly" and not _ps.weekly
          _ps.weekly = true
          _ps  # only return a sub when there's an update
        end
      else
        if params[:type] == "daily"
          ProjectSubscriber.new(user_id: s, project_id: params[:project_id], weekly: false)
        elsif params[:type] == "weekly"
          ProjectSubscriber.new(user_id: s, project_id: params[:project_id], daily: false)
        end 
      end
    end
    
    # @project_subscribers is array of subscribers who are saved successfully
    @project_subscribers.select! { |s| s.save if s != nil }

    #respond_to do |format|
    #  format.html { redirect_to :back }
    #  format.json { head :no_content }
    #  format.js
    #end
  end

	def destroy
    if params[:type] == "daily"
      @project_subscriber.daily = false
    elsif params[:type] == "weekly"
      @project_subscriber.weekly = false
    end

    if !@project_subscriber.daily && !@project_subscriber.weekly
      @project_subscriber.destroy
    else
      @project_subscriber.save
    end

    respond_to do |format|
      format.js 
      format.json { head :no_content }
    end
	end

  # delete a subscription (possibly) other than self's
  def destroy_other
    @project_subscriber = ProjectSubscriber.find(params[:id])
    
    if params[:type] == "daily"
      @project_subscriber.daily = false
    elsif params[:type] == "weekly"
      @project_subscriber.weekly = false
    end

    @self_unsubscribe = @project_subscriber.user_id == current_user.id
    @project = @project_subscriber.project
        
    if !@project_subscriber.daily && !@project_subscriber.weekly
      @project_subscriber.destroy
    else
      @project_subscriber.save
    end
    
    respond_to do |format|
      format.html { redirect_to :back }
      format.js
    end
  end

	private
  
	def set_project_subscriber
    @project_subscriber = ProjectSubscriber.find_by(user_id: params[:user_id], project_id: params[:project_id])
  end

  def set_project
    @project = Project.find(params[:project_id])
  end
end