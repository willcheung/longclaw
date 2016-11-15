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

	def salesforce
		@accounts = Account.eager_load(:projects, :user).where('accounts.organization_id = ? and (projects.id IS NULL OR projects.is_public=true OR (projects.is_public=false AND projects.owner_id = ?))', current_user.organization_id, current_user.id).order("lower(accounts.name)")
		@salesforce_link_accounts = SalesforceAccount.eager_load(:account, :salesforce_opportunities).where('contextsmith_organization_id = ?',current_user.organization_id).is_linked.order("lower(accounts.name)")
	end

	def salesforce_opportunities
		@streams = Project.all.is_active # all active projects because "admin" role can see everything
	end

	def salesforce_activities
		Activity.load_salesforce_activities(Project.find_by_id('6a1d0e56-0e4b-45f6-ac48-3acdaba0ea57'), current_user)
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

	private

	def get_salesforce_user
		# try to get salesforce production. if not connect, check if it is connected to salesforce sandbox
		@salesforce_user = OauthUser.find_by(oauth_provider: 'salesforce', organization_id: current_user.organization_id)
    if(@salesforce_user.nil?)
      @salesforce_user = OauthUser.find_by(oauth_provider: 'salesforcesandbox', organization_id: current_user.organization_id)      
    end
  end
end