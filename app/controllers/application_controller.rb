require 'utils'
require 'contextsmith_parser'

class ApplicationController < ActionController::Base
  include Utils
  include ContextSmithParser

  # Prevent CSRF attacks by raising an exception.
  # For APIs, you may want to use :null_session instead.

  protect_from_forgery with: :null_session, only: Proc.new { |c| c.request.format.json? }
  layout :layout_by_resource
  around_action :set_time_zone, if: :current_user

  def after_sign_in_path_for(resource)
    response.headers["X-FRAME-OPTIONS"] = "ALLOW-FROM na30.salesforce.com"
    if resource.is_a?(User)
      case resource.onboarding_step
      when Utils::ONBOARDING[:onboarded] # Fully onboarded
        stored_location_for(resource) || root_path
      when Utils::ONBOARDING[:confirm_projects]
        if resource.cluster_create_date.nil?
          # Clusters not ready yet
          onboarding_creating_clusters_path
        else
          onboarding_confirm_projects_path
        end
      when Utils::ONBOARDING[:tutorial]
        onboarding_tutorial_path
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

  private

  def set_time_zone(&block)
    if current_user.time_zone == 'UTC' and !cookies[:timezone].nil?
      current_user.update_attributes(time_zone: cookies[:timezone])
    end
    Time.use_zone(current_user.time_zone, &block)
  end
end
