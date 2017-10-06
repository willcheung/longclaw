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
      auth_params = request.env['omniauth.params'] || {}
      request_origin = request.env['omniauth.origin']
      origin = URI.parse(request_origin).path[1..9] if request_origin.present?
      stored_location = stored_location_for(resource)
      location = stored_location[1..9] if stored_location.present?

      # check if sign in from extension, multiple redundancies to make sure extension users stay in extension
      if auth_params['extension'] == 'true' || origin == 'extension' || (location && location.start_with?('extension','plans'))
        if resource.onboarding_step == Utils::ONBOARDING[:fill_in_info]
          onboarding_extension_tutorial_path
        elsif origin.start_with? 'plans'
          plans_path(welcome: true)
        else
          extension_path(login: true)
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
    # whitelist for basic users: extension pages, extension tutorial, extension/tracking related stuff, salesforce login, everything else redirects to access_denied page
    redirect_to home_access_denied_path unless
        %w[extension tracking sessions salesforce omniauth_callbacks plans].include?(params[:controller]) ||
        %w[me access_denied extension_tutorial].include?(params[:action]) ||
        current_user.biz?
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

  def get_close_date_range(range_description)
    case range_description
      when Project::CLOSE_DATE_RANGE[:ThisQuarter]
        date = Time.current
        (date.beginning_of_quarter...date.end_of_quarter)
      when Project::CLOSE_DATE_RANGE[:NextQuarter]
        date = Time.current.next_quarter
        (date.beginning_of_quarter...date.end_of_quarter)
      when Project::CLOSE_DATE_RANGE[:LastQuarter]
        date = Time.current.prev_quarter
        (date.beginning_of_quarter...date.end_of_quarter)
      when Project::CLOSE_DATE_RANGE[:QTD]
        (Time.current.beginning_of_quarter...Time.current)
      when Project::CLOSE_DATE_RANGE[:YTD]
        (Time.current.beginning_of_year...Time.current)
      when Project::CLOSE_DATE_RANGE[:Closed]
        (Time.at(0)...Time.current)
      else # use 'This Quarter' by default
        date = Time.current
        (date.beginning_of_quarter...date.end_of_quarter)
    end
  end

end
