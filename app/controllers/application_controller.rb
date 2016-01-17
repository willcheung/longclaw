require 'utils'
require 'contextsmith_parser'

class ApplicationController < ActionController::Base
  include Utils
  include ContextSmithParser

  # Prevent CSRF attacks by raising an exception.
  # For APIs, you may want to use :null_session instead.

  protect_from_forgery with: :null_session, only: Proc.new { |c| c.request.format.json? }
  layout :layout_by_resource

  def after_sign_in_path_for(resource)
    if resource.is_a?(User)
      case resource.onboarding_step
      when Utils::ONBOARDING[:onboarded] # Fully onboarded
        stored_location_for(resource) || root_path
      # when Utils::ONBOARDING["create_organization"] # Create Organization
      #   new_organization_path 
      when Utils::ONBOARDING[:intro_overall] # Step 1 - Intro
        onboarding_intro_overall_path
      when Utils::ONBOARDING[:intro_accounts_projects] # Step 2 - Accounts, Contacts & Projects
        onboarding_intro_accounts_projects_path
      when Utils::ONBOARDING[:intro_activities] # Step 3 - Activities & News Feed
        onboarding_intro_activites_path
      when Utils::ONBOARDING[:intro_pinned] # Step 4 - Bulletin board. Pin important emails or notes
        onboarding_intro_pinned_path
      when Utils::ONBOARDING[:confirm_projects]
        if resource.cluster_create_date.nil?
          # Clusters not ready yet
          onboarding_creating_clusters_path
        else
          onboarding_confirm_projects_path
        end
      else
        stored_location_for(resource) || root_path
      end
    else
      super
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
