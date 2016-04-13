class NotificationsController < ApplicationController

  def index
     if params[:type]
      projects = Project.visible_to(current_user.organization_id, current_user.id).group("accounts.id").where(category: params[:type]).preload([:users,:contacts,:subscribers])
    else
      projects = Project.visible_to(current_user.organization_id, current_user.id).group("accounts.id").preload([:users,:contacts,:subscribers])
    end
 
    if !projects.empty?
      @notifications = Notification.find_project_and_user(projects.map(&:id))
    else
      @notifications = nil
    end
  end

  def show
    @notification = Notification.find_by_id(params[:id])
  end

	def sasuke
   is_test = true

   Organization.all.each do |org|
      org.accounts.each do |acc| 
        acc.projects.each do |proj|
          # puts "Loading project...\nOrg: " + org.name + ", Account: " + acc.name + ", Project " + proj.name
          ContextsmithService.load_emails_from_backend(proj, nil, 300, nil, true, true, is_test)
          sleep(1)
        end
      end
    end

     # proj = Project.find_by_id("f460b2a2-29f5-4798-a239-b71955c2b96a")
     # ContextsmithService.load_emails_from_backend(proj, nil, 300, nil, true, true, true)

    @notification = Notification.first
   
    render :show
	end



end
