class ProjectMembersController < ApplicationController
  before_action :set_project_member, only: [:destroy]

  def destroy
    project = @project_member.project
    @project_member.destroy
    respond_to do |format|
      format.html { redirect_to project_url(project) }
      format.json { head :no_content }
    end
  end

  private
  def set_project_member
    @project_member = ProjectMember.find(params[:id])
  end

end