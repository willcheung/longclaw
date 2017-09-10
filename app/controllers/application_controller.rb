require 'utils'
require 'contextsmith_parser'

class ApplicationController < ActionController::Base
  include Utils
  include ContextSmithParser

  # Prevent CSRF attacks by raising an exception.
  # For APIs, you may want to use :null_session instead.

  protect_from_forgery with: :null_session, only: Proc.new { |c| c.request.format.json? }
  layout :layout_by_resource
  before_action :restrict_access, if: :current_user
  around_action :set_time_zone, if: :current_user
  around_action :check_google_oauth_valid_token, if: :current_user

  def after_sign_in_path_for(resource)

    if resource.is_a?(User)
      stored_location = stored_location_for(resource)

      if stored_location.present? && stored_location[0..9] == '/extension'
        case resource.onboarding_step
          when Utils::ONBOARDING[:onboarded]
            stored_location || root_path
          when Utils::ONBOARDING[:fill_in_info]
            onboarding_extension_tutorial_path
          else
            stored_location || root_path
        end
      # check if at least biz? level access
      elsif resource.biz?
        case resource.onboarding_step
          when Utils::ONBOARDING[:onboarded] # Fully onboarded
            stored_location || root_path
          when Utils::ONBOARDING[:confirm_projects]
            if resource.cluster_create_date.nil?
              # Clusters not ready yet
              onboarding_creating_clusters_path
            else
              onboarding_confirm_projects_path
            end
          when Utils::ONBOARDING[:tutorial]
            onboarding_tutorial_path
          when Utils::ONBOARDING[:fill_in_info]
            onboarding_fill_in_info_path
          else
            stored_location || root_path
        end
      else
        home_access_denied_path
      end

    else
      super
    end
  end

  def after_sign_out_path_for(resource_or_scope)
    if params[:extension]
      root_path + 'extension'
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

  private

  def restrict_access
    # whitelist for basic users: extension pages, extension tutorial, extension/tracking related stuff, everything else redirects to access_denied page
    redirect_to home_access_denied_path unless params[:controller] == 'extension' || params[:controller] == 'tracking' || params[:controller] == 'sessions' || params[:action] == 'me' || params[:action] == 'access_denied' || params[:action] == 'extension_tutorial' || current_user.biz?
  end

  def set_time_zone(&block)
    if current_user.time_zone == 'UTC' and !cookies[:timezone].nil?
      current_user.update_attributes(time_zone: cookies[:timezone])
    end
    # TODO: Temporarily un-used until figure out why this is buggy (display is off by 1 day)
    #@time_zone_offset_min = -ActiveSupport::TimeZone.new(current_user.time_zone).utc_offset / 60

    Time.use_zone(current_user.time_zone, &block)
  end

  def check_google_oauth_valid_token
    if current_user.oauth_access_token == "invalid"
      reset_session
      session[:redirect_to] = request.referer
      redirect_to session[:redirect_to] || root_path
    end
    yield
  end

  # returns the users of an organization who are registered with CS
  def get_current_org_users
    @users_reverse = current_user.organization.users.registered.order(:first_name).map { |u| [u.id, get_full_name(u)] }.to_h
  end


end
