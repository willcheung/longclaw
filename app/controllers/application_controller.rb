require 'utils'
require 'contextsmith_parser'

class ApplicationController < ActionController::Base
  include Utils
  include ContextSmithParser

  # Prevent CSRF attacks by raising an exception.
  # For APIs, you may want to use :null_session instead.

  protect_from_forgery with: :null_session, only: Proc.new { |c| c.request.format.json? }
  layout :layout_by_resource

  def after_sign_in_path_for(user)
    case user.onboarding_step
    when Utils::ONBOARDING["onboarded"] # Fully onboarded
      root_path 
    when Utils::ONBOARDING["create_organization"] # Create Organization
      new_organization_path 
    when Utils::ONBOARDING["intro_overall"] # Step 1 - Intro
      onboarding_one_path
    when Utils::ONBOARDING["intro_accounts"] # Step 2 - Accounts & Contacts
      
    when Utils::ONBOARDING["intro_projects"] # Step 3 - Project CRM
      
    when Utils::ONBOARDING["intro_activities"] # Step 4 - Activities & News Feed
      
    when Utils::ONBOARDING["intro_pinned"] # Step 5 - Bulletin board. Pin important emails or notes

    when Utils::ONBOARDING["confirm_projects"]
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
