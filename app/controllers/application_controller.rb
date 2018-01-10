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
      request_origin = request.env['omniauth.origin'] || ''
      origin = URI.parse(request_origin).path[1..9] if request_origin.present?
      stored_location = stored_location_for(resource)
      location = stored_location[1..9] if stored_location.present?

      # quick hack to allow Biz sign-ups from this URL
      # if request_origin && request_origin.end_with?('/users/sign_up')
      #  resource.upgrade(:Biz)
      #  resource.save
      # end

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

  # returns array of users (user=[user id, user's full name]) of an organization who are registered with CS
  def get_current_org_users
    @users_reverse = current_user.organization.users.registered.order(:first_name).map { |u| [u.id, get_full_name(u)] }.to_h
  end

  # returns array of opportunity stages of an organization registered with CS
  def get_current_org_opportunity_stages
    @opportunity_stages = SalesforceOpportunity.get_sfdc_opp_stages(organization: current_user.organization).map{|s| s.first}
  end

  # returns array of opportunity forecast categories of an organization registered with CS
  def get_current_org_opportunity_forecast_categories
    @opportunity_forecast_categories = SalesforceOpportunity.get_sfdc_opp_forecast_categories(organization: current_user.organization).map{|s| s.first}
  end


  # Sets the necessary data to be used in the top forecast category and stage reports (in ReportsController and ProjectsController).
  # Parameters:   project_ids (required) - list of CS opportunity id's to filter on.
  #               user_ids (optional) - list of CS user id's on which to filter project owners.
  def set_top_dashboard_data(project_ids: , user_ids: nil)
    if user_ids.present?
      forecast_chart_result = Project.select("COALESCE(projects.forecast, '-Undefined-')").where("projects.id IN (?) AND projects.owner_id IN (?)", project_ids, user_ids).group("COALESCE(projects.forecast, '-Undefined-')").sum("projects.amount").sort
      stage_chart_result = Project.select("COALESCE(projects.stage, '-Undefined-')").where("projects.id IN (?) AND projects.owner_id IN (?)", project_ids, user_ids).group("COALESCE(projects.stage, '-Undefined-')").sum("COALESCE(projects.amount,0)").sort
    else
      forecast_chart_result = Project.select("COALESCE(projects.forecast, '-Undefined-')").where("projects.id IN (?)", project_ids).group("COALESCE(projects.forecast, '-Undefined-')").sum("projects.amount").sort
      stage_chart_result = Project.select("COALESCE(projects.stage, '-Undefined-')").where("projects.id IN (?)", project_ids).group("COALESCE(projects.stage, '-Undefined-')").sum("projects.amount").sort
    end

    winning_stages = stage_chart_result.select{|s,t| current_user.organization.get_winning_stages.include? s}
    @winning_stage_default_name = winning_stages.first[0] if winning_stages.present?
    @lost_won_totals = [[@winning_stage_default_name, winning_stages.sum{|s,t| t}], stage_chart_result.select{|s,t| ['Closed Lost'].include? s}]

    stage_name_picklist = SalesforceOpportunity.get_sfdc_opp_stages(organization: current_user.organization)
    @forecast_chart_data = forecast_chart_result.map do |f, a|
      Hashie::Mash.new({ forecast_category_name: f, total_amount: a })
    end
    @stage_chart_data = stage_chart_result.sort do |x,y|
      stage_name_x = stage_name_picklist.find{|s| s.first == x.first}
      stage_name_x = stage_name_x.present? ? stage_name_x.second.to_s : '           '+x.first
      stage_name_y = stage_name_picklist.find{|s| s.first == y.first}
      stage_name_y = stage_name_y.present? ? stage_name_y.second.to_s : '           '+y.first
      stage_name_x <=> stage_name_y  # unmatched stage names are sorted to the left of everything
    end.map do |s, a|
      Hashie::Mash.new({ stage_name: s, total_amount: a })
    end
  end

end
