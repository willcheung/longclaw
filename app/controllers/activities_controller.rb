class ActivitiesController < ApplicationController
 before_action :set_activity, only: [:update]

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
        format.json { respond_with_bip(@activity)  }
        format.js
      else
        #format.html { render action: 'edit' }
        format.json { render json: @activity.errors, status: :unprocessable_entity }
      end
    end
  end

  def manual_load
  	file = File.open("/Users/willcheung/Downloads/contextsmith-json-3.txt", "r")
	  data = file.read
	  file.close

	  p = Project.find_by_name("Project Galatic Empire")
	  u = User.find_by_email("willycheung@gmail.com")

	  data = JSON.parse(data)
	  data.each do |d|
	  	d["conversations"].each do |c|
	  		Activity.create(
	  										posted_by: u.id,
	  										project_id: p.id,
	  										category: "Conversation",
	  										title: c["subject"],
	  										note: '',
	  										is_public: true,
	  										backend_id: c["id"],
	  										last_sent_date: Time.zone.at(c["lastSentDate"]),
	  										last_sent_date_epoch: c["lastSentDate"],
	  										from: c["contextMessages"][0]["from"],
	  										to: c["contextMessages"][0]["to"],
	  										cc: c["contextMessages"][0]["cc"],
	  										email_messages: c["contextMessages"]
	  										)
	  	end
	  end

	  render text: data
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_activity
      @activity = Activity.find(params[:id])
    end

    # Never trust parameters from the scary internet, only allow the white list through.
    def activity_params
      params.require(:activity).permit(:is_pinned, :pinned_by, :pinned_at, :is_public, :title, :note, :last_sent_date, :last_sent_date_epoch)
    end
end