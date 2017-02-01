require_dependency "app/services/basecamp_service.rb"
class SettingsController < ApplicationController
	before_filter :get_salesforce_user, only: ['salesforce', 'salesforce_opportunities', 'salesforce_activities']

	def index
		@user_count = current_user.organization.users.count
		@registered_user_count = current_user.organization.users.registered.count
		@salesforce_user = OauthUser.find_by(oauth_provider: 'salesforce', organization_id: current_user.organization_id)
    if(@salesforce_user.nil?)
      @salesforce_user = OauthUser.find_by(oauth_provider: 'salesforcesandbox', organization_id: current_user.organization_id)
    end


	end

	def users
		@users = current_user.organization.users
	end

	def alerts
		@risk_settings = current_user.organization.risk_settings.index_by { |rm| RiskSetting::METRIC.key(rm.metric) }

    projects = Project.visible_to(current_user.organization_id, current_user.id).unscope(:group)
		# Average Negative Sentiment Score
		neg_sentiment_scores = Activity.where(project_id: projects.ids, category: Activity::CATEGORY[:Conversation]).select("(jsonb_array_elements(jsonb_array_elements(email_messages)->'sentimentItems')->>'score')::float AS sentiment_score").map { |a| a.sentiment_score }.select { |score| score < -0.75 }
		@avg_neg_sentiment_scores = scale_sentiment_score(neg_sentiment_scores.reduce(0) { |total, score| total + score }.to_f/neg_sentiment_scores.length)

		# Average PctNegSentiment Last 30d
		total_engagement = projects.joins(:activities).where(activities: { category: Activity::CATEGORY[:Conversation], last_sent_date: 30.days.ago.midnight..Time.current }).sum('jsonb_array_length(activities.email_messages)')
		if total_engagement.zero?
			@avg_p_neg_sentiment = 0.0
		else
			total_risks = Activity.where(project_id: projects.ids, category: Activity::CATEGORY[:Conversation], last_sent_date: 30.days.ago.midnight..Time.current).select("(jsonb_array_elements(jsonb_array_elements(email_messages)->'sentimentItems')->>'score')::float AS sentiment_score").map { |a| a.sentiment_score }.select { |score| score < -0.75 }.count
	    @avg_p_neg_sentiment = (total_risks.to_f/total_engagement*100).round(1)
	  end

	  # Average Days Inactive
	  projects_inactivity = projects.group('projects.id').joins(:activities).maximum('activities.last_sent_date') # get last_sent_date of last activity for each project
    projects_inactivity.each { |pid, last_sent_date| projects_inactivity[pid] = last_sent_date.nil? ? 0 : Date.current.mjd - last_sent_date.in_time_zone.to_date.mjd } # convert last_sent_date to days inactive
    @avg_inactivity = (projects_inactivity.reduce(0) { |total, days_inactive| total + days_inactive[1] }.to_f/projects.count).round(1) # get average of days inactive

    # Average Risk Score
    @avg_risk_score = (Project.new_risk_score(projects.ids, current_user.time_zone).reduce(0) { |total, risk_score| total + risk_score[1] }.to_f/projects.count).round(1)
	end

	def create_for_alerts
		if params[:level_type] == "Organization"
			level_id = current_user.organization.id
		end
		risk_settings = RiskSetting.where(level_type: params[:level_type], level_id: level_id)
		new_settings = params['settings']
		new_settings.each do |metric, settings|
			rs = risk_settings.find_by_metric(RiskSetting::METRIC[metric.to_sym])
			settings.each do |prop, value|
				value = value.to_f/100 if (metric == 'PctNegSentiment' && (prop == 'medium_threshold' || prop == 'high_threshold')) || prop == 'weight'
				rs[prop] = value
			end
			rs.notify_task = settings['notify_task'] == 'on'
			rs.save
		end

		redirect_to :back
	end

	def salesforce
		@accounts = Account.eager_load(:projects, :user).where('accounts.organization_id = ? and (projects.id IS NULL OR projects.is_public=true OR (projects.is_public=false AND projects.owner_id = ?))', current_user.organization_id, current_user.id).order("lower(accounts.name)")
		@salesforce_link_accounts = SalesforceAccount.eager_load(:account, :salesforce_opportunities).where('contextsmith_organization_id = ?',current_user.organization_id).is_linked.order("lower(accounts.name)")
	end

	def salesforce_opportunities
		@streams = Project.all.is_active # all active projects because "admin" role can see everything
	end

	def salesforce_activities
		@streams = Project.all.is_active.includes(:salesforce_opportunities) # all active projects because "admin" role can see everything
	end

	def basecamp
		@basecamp2_user = OauthUser.find_by(oauth_provider: 'basecamp2', organization_id: current_user.organization_id)
		pin = params[:code]
		# Check if Oauth_user has been created
		if @basecamp2_user == nil && pin
			# Check if User exist in our database
			# This Creates a new Oauth_user
			begin
				OauthUser.basecamp2_create_user(pin, current_user.organization_id)
			rescue
				#code that deals with some exception
				flash[:warning] = "Has not been registered succesfully"
			else
				#code that runs only if (no) excpetion was raised
				flash[:notice] = "Basecamp is enabled!"
			end
		end

		# if @basecamp2_user

		# 	puts "settings controller:======#{@basecamp2_user['oauth_access_token']}"
		# 	response = OauthUser.basecamp2_projects(@basecamp2_user['oauth_access_token'])
		# 	puts "#{response}"

		# end

	end

	def super_user
		@super_admin = %w(wcheung@contextsmith.com rcwang@contextsmith.com)
		if @super_admin.include?(current_user.email)
			@users = User.registered.all
		else
			redirect_to root_path
		end
	end

	def invite_user
		@user = User.find_by_id(params[:user_id])

		UserMailer.user_invitation_email(@user, get_full_name(current_user), new_user_registration_url(invited_by: current_user.first_name)).deliver_later

		respond_to do |format|
			format.js
		end
	end

	def iframe_test
		render layout: "empty"
	end

	def chrome_gmail_plugin
		render layout: "empty"
	end

	private

	def get_salesforce_user
		# try to get salesforce production. if not connect, check if it is connected to salesforce sandbox
		@salesforce_user = OauthUser.find_by(oauth_provider: 'salesforce', organization_id: current_user.organization_id)
    if(@salesforce_user.nil?)
      @salesforce_user = OauthUser.find_by(oauth_provider: 'salesforcesandbox', organization_id: current_user.organization_id)
    end
  end
end
