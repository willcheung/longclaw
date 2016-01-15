class OnboardingController < ApplicationController
	layout 'empty'

	def intro_overall

	end

	def intro_accounts_projects

	end

	def intro_activities

	end

	def intro_pinned

	end

	# Callback method
	def confirm_projects
		@overlapping_projects = []
		@new_projects = []
		@same_projects = []

		new_user_projects = Project.where(created_by: current_user.id, is_confirmed: false).includes(:users, :contacts, :account)
		all_accounts = current_user.organization.accounts.includes(projects: [:users, :contacts])

		new_user_projects.each do |new_project|
			new_project_members = new_project.contacts.map(&:email).map(&:downcase).map(&:strip)
			
			all_accounts.each do |account |
				if account == new_project.account
					overlapping_p = []
					new_p = []
					same_p = []

					#puts "---Account is " + account.name + "---"

					account.projects.each do |existing_project|
						existing_project_members = existing_project.contacts.map(&:email).map(&:downcase).map(&:strip)
						
						# DEBUG MSG
						# puts existing_project_members
						# puts "----"
						# puts new_project_members

						dc = dice_coefficient(existing_project_members, new_project_members)
						intersect = intersect(existing_project_members, new_project_members)
						logger.info("Dice Coefficient #{dc}, Intersect #{intersect}")
						ahoy.track("Project Confirmation", dice_coefficient: dc, intersect: intersect, existing_project_members: existing_project_members, new_project_members: new_project_members)

						# puts "\n\n\n\n"

						if dc == 1.0
							# 100% match. Do not display these projects.
							same_p << existing_project
						elsif dc < 1.0 and dc >= 0.25
							# Considered same project. 
							overlapping_p << existing_project
						elsif dc < 0.25 and dc > 0.0 and intersect > 1
							# Considered existing projects because there are more than 1 shared members.
							overlapping_p << existing_project
						elsif dc < 0.25 and dc > 0.0 and intersect == 1
							# This is likely a one-time communication or a typo by email sender.
							if existing_project.users.map(&:email).include?(current_user.email)
								overlapping_p << existing_project
							else
								new_p << new_project if !new_p.include?(new_project)
							end
						else dc == 0.0 
							# Definitely new project.  Modify new project into confirmed project.
							new_p << new_project if !new_p.include?(new_project)
						end
					end

					# Take action on the unconfirmed projects
					if account.projects.size == 0
						# Add project into account.  Modify new project into confirmed project
						new_project.update_attributes(is_confirmed: true)
					elsif overlapping_p.size > 0
						overlapping_p.each do |p|
							p.project_members.create(user_id: current_user.id)
							
							new_project.contacts.each do |c|
								p.project_members.create(contact_id: c.id)
							end

							new_project.users.each do |u|
								p.project_members.create(user_id: u.id)
							end
						end
						new_project.destroy # Delete unconfirmed project
					else # No overlapping projects
						if same_p.size > 0
							same_p.each do |p|
								p.project_members.create(user_id: current_user.id)
							end
							new_project.destroy # Delete unconfirmed project
						elsif new_p.size > 0
							new_project.update_attributes(is_confirmed: true)
						end
					end

					overlapping_p.each { |p| @overlapping_projects << p }
					new_p.each { |p| @new_projects << p }
					same_p.each { |p| @same_projects << p }
				end
			end
		end
	end

	#########################################################################
	# Callback method from backend to create clusters for a particular user 
	#
	# Example: 	 curl -H "Content-Type: application/json" --data @/Users/willcheung/Downloads/contextsmith-json-3.txt http://localhost:3000/onboarding/64eb67f6-3ed1-4678-84ab-618d348cdf3a/create_clusters.json
	# Example 2: http://64.201.248.178/:8888/newsfeed/cluster?email=indifferenzetester@gmail.com&token=test&max=300&before=1408695712&in_domain=comprehend.com&callback=http://24.130.10.244:3000/onboarding/64eb67f6-3ed1-4678-84ab-618d348cdf3a/create_clusters.json
	#
	#########################################################################

	def create_clusters
		user = User.find_by_id(params[:user_id])
		data = params["_json"]

		respond_to do |format|
      
  		if user and data
        begin
          uniq_external_members, uniq_internal_members = get_all_members(data)

          ############## Needs to be called in order -> Account (Contacts), User, Project ##########

	        # Create Accounts and Contacts
	       	Account.create_from_clusters(uniq_external_members, user.id, user.organization.id)

	       	# Create internal users
	       	User.create_from_clusters(uniq_internal_members, user.id, user.organization.id)

	       	# Create Projects, project members, and activities
	       	Project.create_from_clusters(data, user.id, user.organization.id)

	       	########################################################

	       	# Update flag indicating cluster creation is complete
	       	if user.cluster_create_date.nil?
	       		user.update_attributes(cluster_create_date: Time.now, cluster_update_date: Time.now)
	       	else
	       		user.update_attributes(cluster_update_date: Time.now)
	       	end

        rescue => e
          format.json { render json: 'ERROR: Something went wrong: ' + e.to_s, status: 500}
          logger.error "ERROR: Something went wrong: " + e.message
          logger.error e.backtrace.join("\n")
          ahoy.track("Error Create Cluster", message: e.message, backtrace: e.backtrace.join("\n"))
        else
          format.json { render json: 'Clusters created for user ' + user.email, status: 200}
        end
  		elsif user.nil?
  			format.json { render json: 'User not found.', status: 500}
  			logger.error "ERROR: User not found: " + params[:user_id]
  			ahoy.track("Error Create Cluster", message: "User not found: #{params[:user_id]}")
  		elsif data.nil?
  			format.json { render json: 'No data.', status: 200}

  			if params["errors"].nil? # no errors
	  			logger.error "No data return for user: " + params[:user_id]
	  			ahoy.track("Error Create Cluster", message: "No data return for user: #{params[:user_id]}")
	  		else # returns error
	  			logger.error "ERROR: Code: " + params[:code].to_s + " Error: " + params["message"]
	  			ahoy.track("Error Create Cluster", message: "#{params[:code].to_s} #{params[:message]}")
	  			if params["message"] == "Invalid Credentials"
	  				logger.error "Token might have expired."
	  				ahoy.track("Error Create Cluster", message: "Invalid Credentials. Token might have expired.")
	  			end
	  		end
  		end
  	end
	end
end