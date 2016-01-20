class ActivitiesController < ApplicationController
 before_action :set_comment, only: [:update]

  def update
    respond_to do |format|
      if @activity.update_attributes(activity_params)
        #format.html { redirect_to @activity, notice: 'Activity was successfully updated.' }
        format.json { head :no_content }
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
    def set_comment
      @activity = Activity.find(params[:id])
    end

    # Never trust parameters from the scary internet, only allow the white list through.
    def activity_params
      params.require(:activity).permit(:is_pinned, :pinned_by, :is_public, :title, :note)
    end
end