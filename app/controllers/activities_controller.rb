class ActivitiesController < ApplicationController
 before_action :set_activity, only: [:update, :destroy]

 	def create
 		project = Project.find_by_id(params[:project_id])
 		@activity = project.activities.new(activity_params.merge(category: "Note", title: "", posted_by: current_user.id, is_public: true, last_sent_date: Time.now, last_sent_date_epoch: Time.now.to_i))

 		respond_to do |format|
      if @activity.save
        #format.html { redirect_to @activity, notice: 'Activity was successfully created.' }
        format.json { render action: 'show', status: :created, location: @activity }
        format.js
      else
        #format.html { render action: 'new' }
        format.json { render json: @activity.errors, status: :unprocessable_entity }
      end
    end
 	end

  def update
    respond_to do |format|

    	if activity_params[:is_pinned] == "true"
    		params = activity_params.merge(pinned_at: Time.now, pinned_by: current_user.id)
    	else
    		params = activity_params
    	end

      if @activity.update_attributes(params)
        #format.html { redirect_to @activity, notice: 'Activity was successfully updated.' }
        format.json { respond_with_bip(@activity) }
        format.js
      else
        #format.html { render action: 'edit' }
        format.json { render json: @activity.errors, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    project = @activity.project
    @activity.destroy
    respond_to do |format|
      format.html { redirect_to project_url(project) }
      format.json { head :no_content }
      format.js
    end
  end


  private
    # Use callbacks to share common setup or constraints between actions.
    def set_activity
      @activity = Activity.find(params[:id])
    end

    # Never trust parameters from the scary internet, only allow the white list through.
    def activity_params
      params.require(:activity).permit(:is_pinned, :pinned_by, :pinned_at, :is_public, :title, :note, :last_sent_date, :last_sent_date_epoch, :rag_score)
    end
end
