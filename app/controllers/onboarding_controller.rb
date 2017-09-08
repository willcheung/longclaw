require 'net/http'
require "erb"
include ERB::Util

class OnboardingController < ApplicationController
	layout 'empty', except: ['tutorial', 'extension_tutorial']
	# layout false, only: ['tutorial', 'extension_tutorial']

  def fill_in_info
    start_new_user
  end

  def extension_tutorial
    render layout: false
    start_new_user(Utils::ONBOARDING[:onboarded])
  end

	def tutorial
    render layout: false
		# change user onboarding status
		if current_user.mark_private == true # Skip this step if you're VP level or above (all 1-1 e-mails are private)
			current_user.update_attributes(onboarding_step: Utils::ONBOARDING[:onboarded])
		else
			current_user.update_attributes(onboarding_step: Utils::ONBOARDING[:confirm_projects]) if current_user.onboarding_step == Utils::ONBOARDING[:tutorial]
		end
  end

  # Show the user the onboarding "Processing e-mails" in-progress page.
	def creating_clusters
		if current_user.onboarding_step == Utils::ONBOARDING[:confirm_projects] and !current_user.cluster_create_date.nil?
			redirect_to onboarding_confirm_projects_path
		elsif current_user.onboarding_step == Utils::ONBOARDING[:onboarded]
			redirect_to root_path
		end
	end

	# Allow user to confirm processed clusters (in the form of opportunities/projects)
	def confirm_projects
		return_vals = User.confirm_projects_for_user(current_user)

		redirect_to root_path and return if return_vals == -1 

    @overlapping_projects = return_vals[:overlapping_projects]
    @new_projects = return_vals[:new_projects]
    @same_projects = return_vals[:same_projects]
    @account_types = return_vals[:account_types]
    @project_last_email_date = return_vals[:project_last_email_date]
	end

	#########################################################################
	# Callback method from backend during onboarding process to create clusters for a particular user 
	#
	# Example: 	 curl -H "Content-Type: application/json" --data @/Users/willcheung/Downloads/contextsmith-json-3.txt http://localhost:3000/onboarding/64eb67f6-3ed1-4678-84ab-618d348cdf3a/create_clusters.json
	# Example 2: http://64.201.248.178/:8888/newsfeed/cluster?email=indifferenzetester@gmail.com&token=test&max=300&before=1408695712&in_domain=comprehend.com&callback=http://24.130.10.244:3000/onboarding/64eb67f6-3ed1-4678-84ab-618d348cdf3a/create_clusters.json
	#
	#########################################################################

	def create_clusters
      user = User.find_by_id(params[:user_id])
      data = params["_json"]

      respond_to do |format|
        if user and data.kind_of?(Array)   
            puts("Creating Opportunities for #{user.email}")

            uniq_external_members, uniq_internal_members = get_all_members(data)

            ############## Needs to be called in order -> Account (Contacts), User, Project ##########

            puts "Create accounts and contacts..."
            Account.create_from_clusters(uniq_external_members, user.id, user.organization_id)

            puts "Create internal users..."
            User.create_from_clusters(uniq_internal_members, user.id, user.organization_id)

            puts "Create projects, project members, and activities..."
            Project.create_from_clusters(data, user.id, user.organization_id)

            ##########################################################################################

        elsif user.nil?
            format.json { render json: 'User not found.', status: 500}
            puts "ERROR: User not found: " + params[:user_id]
            ahoy.track("Error Create Cluster", message: "User not found: #{params[:user_id]}")
            raise "ERROR: User not found during callback: " + params[:user_id]
            return nil

        elsif data.nil? or data.empty?

            if params['code'] == 401 # Invalid credentials
              puts "ERROR: #{params['message']}\n"
                ahoy.track("Error Create Cluster for " + params[:user_id], message: "#{params['message']}")
                raise "ERROR: Invalid credential during callback: " + params[:user_id]
                return nil

            elsif params['code'] == 404 # No external cluster found
              puts "ERROR: #{params['message']}"
              ahoy.track("Error Create Cluster for " + params[:user_id], message: "#{params['message']}")
            end
        else
            puts "Unhandled backend response #{params['message']}"
                ahoy.track("Error Create Cluster for " + params[:user_id], message: "Unhandled backend response #{params['message']}.")
                raise "ERROR: Unhandled backend response during callback: " + params[:user_id]
            return nil

        end # if user and data

      begin
        # Update flag indicating cluster creation is complete
        if user.cluster_create_date.nil?
            user.update_attributes(cluster_create_date: Time.now, cluster_update_date: Time.now)
        else
            user.update_attributes(cluster_update_date: Time.now)
        end

        # Send welcome e-mail with confirm_projects link
        num_of_projects = Project.where(created_by: user.id, is_confirmed: false).includes(:users, :contacts, :account).count(:projects)
        puts("Sending onboarding email to #{user.email}")
        url = ENV["BASE_URL"] + "/onboarding/confirm_projects"
        UserMailer.welcome_email(user, num_of_projects, url).deliver_later
        
        format.json { render json: 'E-mail sent to ' + user.email, status: 200 }

      rescue => e
        format.json { render json: 'ERROR: Something went wrong: ' + e.to_s, status: 500}
        puts "ERROR: Something went wrong: " + e.message
        puts e.backtrace.join("\n")
        ahoy.track("Error Create Cluster", message: e.message, backtrace: e.backtrace.join("\n"))
      else
        format.json { render json: 'Clusters created for user ' + user.email, status: 200}
      end
    end # respond_to do |format|
  end # END: create_clusters

  private

  def start_new_user(step=Utils::ONBOARDING[:tutorial])
    # change user onboarding status and cluster_create_date becomes join date
    current_user.update(onboarding_step: step) if current_user.onboarding_step == Utils::ONBOARDING[:fill_in_info]
    if Rails.env.production?
      list_id = ENV['mailchimp_email_list_id']
      # Using MailChimp for email automation. User's domain will be sent to ContextSmith Trial Newsletter
      uri = URI('https://us13.api.mailchimp.com/3.0/lists/' + list_id + '/members/')
      res = Net::HTTP.start(uri.host, uri.port, :use_ssl => uri.scheme == 'https') do |http|
        req = Net::HTTP::Post.new(uri)
        req['Content-Type'] = 'application/json'
        req.basic_auth 'anystring', ENV["mailchimp_api_key"]
        json_data = {'email_address' => current_user.email, 'status' => 'subscribed', "merge_fields" => {"FNAME"=>"#{current_user.first_name}","LNAME" => "#{current_user.last_name}"} }.to_json
        req.body = json_data
        response = http.request(req) # Net::HTTPResponse object
      end
      # MailChimp API call takes a few minutes before contact is added to the mailchimp list
    end
    # Alert the CS team when a new user has signed up to our platform! Need to revise once this becomes too noisy
    UserMailer.update_cs_team(current_user).deliver_now
  end
end