class SettingsController < ApplicationController
	before_filter :get_basecamp2_user, only: ['basecamp','basecamp2_projects', 'basecamp2_activity']
	before_filter :get_salesforce_admin_user, only: ['index', 'salesforce_accounts', 'salesforce_opportunities', 'salesforce_activities', 'salesforce_fields']

	def index
		@user_count = current_user.organization.users.count
		@registered_user_count = current_user.organization.users.registered.count
		@basecamp2_user = OauthUser.find_by(oauth_provider: 'basecamp2', organization_id: current_user.organization_id)

		if (@salesforce_user.nil? && # could not connect via organization/admin login
				current_user.power_or_trial_only?)  # AND is an individual (power user or trial/Chrome user)
			@individual_salesforce_user = OauthUser.find_by(oauth_provider: 'salesforce', organization_id: current_user.organization_id, user_id: current_user.id)
			@individual_salesforce_user = OauthUser.find_by(oauth_provider: 'salesforcesandbox', organization_id: current_user.organization_id, user_id: current_user.id) if @individual_salesforce_user.nil?
		end

		@current_user_projects = current_user.projects.where('projects.is_confirmed = true AND projects.status = \'Active\'')
		@current_user_subscriptions = current_user.valid_streams_subscriptions
	end

	def users
		@users = current_user.organization.users
	end

	def alerts
		@risk_settings = current_user.organization.risk_settings.index_by { |rm| RiskSetting::METRIC.key(rm.metric) }

    projects = Project.visible_to(current_user.organization_id, current_user.id).unscope(:group)
		# Average Negative Sentiment Score
		neg_sentiment_scores = Activity.where(project_id: projects.ids, category: Activity::CATEGORY[:Conversation]).select("(jsonb_array_elements(jsonb_array_elements(email_messages)->'sentimentItems')->>'score')::float AS sentiment_score").map { |a| a.sentiment_score }.select { |score| score < -0.75 }
		tmp_score = neg_sentiment_scores.reduce(0) { |total, score| total + score }.to_f/neg_sentiment_scores.length
    if neg_sentiment_scores.empty?
      @avg_neg_sentiment_scores = 0
    else
      @avg_neg_sentiment_scores = tmp_score.nan? ? 0 : scale_sentiment_score(tmp_score)
    end

    # Average Days Inactive
    projects_inactivity = projects.group('projects.id').joins(:activities).where.not(activities: { category: [Activity::CATEGORY[:Note], Activity::CATEGORY[:Alert]] }).maximum('activities.last_sent_date') # get last_sent_date of last activity for each project
    if projects_inactivity.empty?  # if projects is empty, inactivity should be too
      @avg_inactivity = 0
    else
      projects_inactivity.each { |pid, last_sent_date| projects_inactivity[pid] = last_sent_date.nil? ? 0 : Date.current.mjd - last_sent_date.in_time_zone.to_date.mjd } # convert last_sent_date to days inactive
      @avg_inactivity = (projects_inactivity.reduce(0) { |total, days_inactive| total + days_inactive[1] }.to_f/projects.count).round(1) # get average of days inactive
    end

    # "Total Risk Score"
    if projects.empty?
      @avg_risk_score = 0
    else
      @avg_risk_score = (Project.new_risk_score(projects.ids, current_user.time_zone).reduce(0) { |total, risk_score| total + risk_score[1] }.to_f/projects.count).round(1)
    end
	end

	def create_for_alerts
		if params[:level_type] == "Organization"
			level_id = current_user.organization_id
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

	# An index of all the Custom Fields for the current user's organization, by entity type.
	# Parameters: entity_type: = "Account" by default
	def custom_fields
		@entity_type = CustomFieldsMetadatum.validate_and_return_entity_type(params[:entity_type], true) || CustomFieldsMetadatum::ENTITY_TYPE[:Account]

		@custom_fields = current_user.organization.custom_fields_metadatum.where(entity_type:@entity_type) 
		@custom_lists = current_user.organization.get_custom_lists(25)
	end

	# An index of all the Custom Lists for the current user's organization
	def custom_lists
		@custom_lists = current_user.organization.custom_lists_metadatum
	end

	# An index of all the Custom Fields for the current user's organization
	def custom_list_show
		begin
			@custom_list_metadata = current_user.organization.custom_lists_metadatum.find(params[:id])
		rescue ActiveRecord::RecordNotFound
			redirect_to root_url, :flash => { :error => "Custom List not found or is private." }
		end
	end

	# Map CS Accounts with Salesforce accounts: "One CS Account can link to many Salesforce Accounts"
	def salesforce_accounts
		if current_user.role == User::ROLE[:Admin]
			@accounts = Account.eager_load(:projects, :user).where("accounts.organization_id = ?", current_user.organization_id).order("upper(accounts.name)")

			@salesforce_link_accounts = SalesforceAccount.eager_load(:account, :salesforce_opportunities).where('contextsmith_organization_id = ?',current_user.organization_id).is_linked.order("upper(accounts.name)")
		end
		@linked_to_sfdc = @salesforce_link_accounts.present?
	end

	# Map CS Streams with Salesforce Opportunities: "One CS Stream can link to many Salesforce Opportunities"
	def salesforce_opportunities
		if current_user.role == User::ROLE[:Admin]
			@streams = Project.visible_to_admin(current_user.organization_id).is_active.is_confirmed.sort_by { |s| s.name.upcase } # all active projects because "admin" role can see everything
			@salesforce_link_opps = SalesforceOpportunity.select('salesforce_opportunities.*, salesforce_accounts.salesforce_account_name').joins('JOIN salesforce_accounts on salesforce_accounts.salesforce_account_id = salesforce_opportunities.salesforce_account_id').where("salesforce_accounts.contextsmith_organization_id=? AND contextsmith_project_id IS NOT NULL", "#{current_user.organization_id}")
		end
	end

	def salesforce_activities
		if current_user.role == User::ROLE[:Admin]
			@CS_ACTIVITY_SFDC_EXPORT_SUBJ_PREFIX = Activity::CS_ACTIVITY_SFDC_EXPORT_SUBJ_PREFIX
			@streams = Project.visible_to_admin(current_user.organization_id).is_active.is_confirmed.includes(:salesforce_opportunity, :account).group("salesforce_opportunities.id, accounts.id").sort_by { |s| s.name.upcase }  # all active projects because "admin" role can see everything

			# Load previous queries if it was saved
			custom_config = current_user.organization.custom_configurations.where("organization_id = '#{current_user.organization_id}' AND config_type LIKE '/settings/salesforce_activities#%'")

			@entity_predicate = custom_config.where(config_type: "/settings/salesforce_activities#salesforce-activity-entity-predicate-textarea")
			if @entity_predicate.empty?
				@entity_predicate = current_user.organization.custom_configurations.create(config_type: "/settings/salesforce_activities#salesforce-activity-entity-predicate-textarea", config_value: "") 
			else
				@entity_predicate = @entity_predicate.first
			end
			@activityhistory_predicate = custom_config.where(config_type: "/settings/salesforce_activities#salesforce-activity-activityhistory-predicate-textarea")
			if @activityhistory_predicate.empty?
				@activityhistory_predicate = current_user.organization.custom_configurations.create(config_type: "/settings/salesforce_activities#salesforce-activity-activityhistory-predicate-textarea", config_value: "") 
			else
				@activityhistory_predicate = @activityhistory_predicate.first
			end

			# to decide if show "update SFDC ActivityHistory" export button
			@super_admin = %w(wcheung@contextsmith.com syong@contextsmith.com vluong@contextsmith.com klu@contextsmith.com beders@contextsmith.com)
		end
	end

	# Map SFDC entity fields to standard or custom CS entity fields
	def salesforce_fields
		if current_user.role == User::ROLE[:Admin]
      @user_roles = User::ROLE.map { |r| [r[1],r[1]] }

      if params[:type] == "standard"
        cs_entity_fields = current_user.organization.entity_fields_metadatum.order(:name)
        @cs_account_fields = cs_entity_fields.where(entity_type: EntityFieldsMetadatum::ENTITY_TYPE[:Account])
        @cs_stream_fields = cs_entity_fields.where(entity_type: EntityFieldsMetadatum::ENTITY_TYPE[:Stream])
        @cs_contact_fields = cs_entity_fields.where(entity_type: EntityFieldsMetadatum::ENTITY_TYPE[:Contact])
      elsif params[:type] == "custom"
        cs_custom_fields = current_user.organization.custom_fields_metadatum.order(:name)
        @cs_account_custom_fields = cs_custom_fields.where(entity_type: CustomFieldsMetadatum::ENTITY_TYPE[:Account])
        @cs_stream_custom_fields = cs_custom_fields.where(entity_type: CustomFieldsMetadatum.validate_and_return_entity_type(CustomFieldsMetadatum::ENTITY_TYPE[:Project], true))
      end

      # We don't save SFDC custom fields (i.e., in our backend), so we query SFDC every time! :(
			if (params[:sfdc_custom_fields_only] == "true")
        @sfdc_fields = SalesforceController.get_salesforce_fields(organization_id: current_user.organization_id, custom_fields_only: true)
			else
        @sfdc_fields = SalesforceController.get_salesforce_fields(organization_id: current_user.organization_id)
			end

			if @sfdc_fields.empty?  # SFDC connection error
				@salesforce_connection_error = true
			else
				EntityFieldsMetadatum.create_default_for(current_user.organization) if current_user.organization.entity_fields_metadatum.first.present?  # SFDC connection exists, so check if mapping exists; if not, create a default mapping to SFDC fields

				# add ("nil") options to remove mapping 
				@sfdc_fields[:sfdc_account_fields] << ["","(Unmapped)"] 
				@sfdc_fields[:sfdc_opportunity_fields] << ["","(Unmapped)"] 
				@sfdc_fields[:sfdc_contact_fields] << ["","(Unmapped)"] 
				#puts "******** @sfdc_fields *** #{@sfdc_fields} *******"
			end
		end
	end

	def basecamp
		@basecamp2_user = OauthUser.find_by(oauth_provider: 'basecamp2', organization_id: current_user.organization_id)
		# Filter only the users Accounts
		@streams = Project.visible_to_admin(current_user.organization_id).is_active
		# @accounts = Account.eager_load(:projects, :user).where('accounts.organization_id = ? and (projects.id IS NULL OR projects.is_public=true OR (projects.is_public=false AND projects.owner_id = ?))', current_user.organization_id, current_user.id).order("lower(accounts.name)")
		callback_pin = params[:code]
		# Check if Oauth_user has been created
		if @basecamp2_user == nil && callback_pin
			# Check if User exist in our database
			# This Creates a new Oauth_user
			begin
				OauthUser.basecamp2_create_user(callback_pin, current_user.organization_id, current_user.id)
			rescue
				#code that deals with some exception
				flash[:warning] = "Sorry something went wrong"
			else
				#code that runs only if (no) excpetion was raised
				flash[:notice] = "Connected to BaseCamp2"
			end
		end
	end

	def basecamp2_projects
			@accounts = Project.where(account_id: params[:account_id]).where(organization_id:current_user.organization_id)
	end

	def super_user
		@super_admin = %w(wcheung@contextsmith.com syong@contextsmith.com vluong@contextsmith.com klu@contextsmith.com beders@contextsmith.com)
		if @super_admin.include?(current_user.email)
			@users = User.all.includes(:organization).order(:onboarding_step).group_by { |u| u.organization }
		else
			redirect_to root_path
		end
	end

	def user_analytics
		@super_admin = %w(wcheung@contextsmith.com syong@contextsmith.com vluong@contextsmith.com klu@contextsmith.com beders@contextsmith.com)
		if @super_admin.include?(current_user.email)
			@users = User.all.includes(:organization).order(:onboarding_step).group_by { |u| u.organization }
			@institution = Organization.all
			@latest_user_activity = Ahoy::Event.latest_activities
			activity_org = Ahoy::Event.all_ahoy_events
			@event_date = activity_org.map(&:date)
			@event_count = activity_org.map{ |n| n['events']}
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

	private

	# Gets SFDC connection for Organization (a single SFDC admin login only)
	def get_salesforce_admin_user
		if current_user.admin?
			# try to get salesforce production. if not connect, check if it is connected to Salesforce sandbox
			@salesforce_user = OauthUser.find_by(oauth_provider: 'salesforce', organization_id: current_user.organization_id)
			if(@salesforce_user.nil?)
			  @salesforce_user = OauthUser.find_by(oauth_provider: 'salesforcesandbox', organization_id: current_user.organization_id)
			end
		else
			@salesforce_user = nil
		end
  end

  def get_basecamp2_user
		@basecamp2_user = OauthUser.find_by(oauth_provider: 'basecamp2', organization_id: current_user.organization_id)
		# @basecamp2_user = nil
		if @basecamp2_user
			# Look to find only the current users connections
			@basecamp_connections = Integration.find_basecamp_connections
			@basecamp_projects = OauthUser.basecamp2_projects(@basecamp2_user['oauth_access_token'], @basecamp2_user['oauth_instance_url'])
		end
	end

end
