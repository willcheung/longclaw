class ProjectMembersController < ApplicationController
  before_action :set_project_member, only: [:destroy, :update]

  def destroy
    project = @project_member.project
    @prev_status = @project_member.status
    @project_member.status = ProjectMember::STATUS[:Rejected]
    @project_member.save
    respond_to do |format|
      format.html { redirect_to project_url(project) }
      format.json { head :no_content }
      format.js
    end
  end

  def update
    project = @project_member.project
    @project_member.status = ProjectMember::STATUS[:Confirmed]
    @project_member.save
    respond_to do |format|
      format.html { redirect_to project_url(project) }
      format.json { head :no_content }
      format.js
    end
  end

  def create
    @project_members = []
    emails = params[:email].split(',')
    emails.each do |email|
      user = current_user.organization.users.find_by_email(email)
      if user
        project_member = ProjectMember.find_or_initialize_by(project_id: params[:project_id], user: user) if user
      else
        contact = Contact.visible_to(current_user).find_by_email(email)
        project_member = ProjectMember.find_or_initialize_by(project_id: params[:project_id], contact: contact) if contact
      end

      next if project_member.blank? || (project_member.id.present? && project_member.status == ProjectMember::STATUS[:Confirmed])
      project_member.status = ProjectMember::STATUS[:Confirmed]

      if project_member.save
        @project_members.push(project_member)
      else
        puts "Error: Add project member fail!"
        ahoy.track("Error add project member", message: project_member.errors.full_messages)
        # puts project_member.errors.full_messages
      end
    end

    respond_to do |format|
        format.html { redirect_to project_path(params[:project_id]) }
        format.js
    end
  end    

  # GET /project_members/new
  def new
    @project_member = ProjectMember.new
  end

  private
  def set_project_member
    @project_member = ProjectMember.find(params[:id])
  end
end