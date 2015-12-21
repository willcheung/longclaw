require 'utils'
require 'contextsmith_parser'

class ApplicationController < ActionController::Base
  include ContextSmithParser
  include Utils

  # Prevent CSRF attacks by raising an exception.
  # For APIs, you may want to use :null_session instead.

  protect_from_forgery with: :null_session, only: Proc.new { |c| c.request.format.json? }
  layout :layout_by_resource

  def after_sign_in_path_for(user)
    case user.onboarding_step
    when -1 # Fully onboarded
      root_path 
    when 0 # Create Organization
      new_organization_path 
    when 1 # Step 1 - Intro
      onboarding_one_path
    when 2 # Step 2 - Project CRM
      
    when 3 # Step 3 - Activity news feed
      
    when 4 # Step 4 - Bulletin board. Pin important emails or notes
      
    when 5 # Confirm projects
      if user.cluster_create_date.nil?
        # Clusters not ready yet
      else

      end
    else
      root_path
    end
  end

  protected

  def layout_by_resource
    if devise_controller?
      "empty"
    else
      "application"
    end
  end
end
