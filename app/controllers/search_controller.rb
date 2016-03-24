class SearchController < ApplicationController

	def results
  	@title = "Results"
		#@notes = Activity.search_note(params[:query]).where("is_public = true and category='Note'") # TO DO need to filter by project
		@project = Project.visible_to(current_user.organization_id, current_user.id).where("projects.id = ?", params[:project_id]).first
		@activities = ContextsmithService.load_emails_from_backend(@project, nil, 100, params[:query], false)
  end

  # Rolling our own autocomplete handler because of visible_to project scope
  def autocomplete_project_name
  	@projects = Project.visible_to(current_user.organization_id, current_user.id).where("lower(projects.name) like ?", "%#{params[:term]}%")
  	
  	respond_to do |format|
  		format.json { render json: @projects.map { |x| { :label => x.name, :value => "#" + x.name, :account => x.account.name } }.to_json.html_safe }
  	end
  end
end