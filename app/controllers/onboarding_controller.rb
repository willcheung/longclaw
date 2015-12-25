class OnboardingController < ApplicationController
	layout 'empty'

	def one

	end

	def two

	end

	def three

	end

	def four

	end

	def confirm_projects

	end

	#########################################################################
	# Callback method from backend to create clusters for a particular user 
	#
	# Example: 	 curl -H "Content-Type: application/json" --data @/Users/willcheung/Downloads/contextsmith-json-3.txt http://localhost:3000/onboarding/64eb67f6-3ed1-4678-84ab-618d348cdf3a/create_clusters.json
	# Example 2: http://192.168.1.130:8888/newsfeed/cluster?email=indifferenzetester@gmail.com&token=test&max=300&before=1408695712&in_domain=comprehend.com&callback=http://24.130.10.244:3000/onboarding/64eb67f6-3ed1-4678-84ab-618d348cdf3a/create_clusters.json
	#
	#########################################################################

	def create_clusters
		user = User.find_by_id(params[:user_id])
		data = params["_json"]

		respond_to do |format|
      puts format.to_s
  		if user and data
        begin
          uniq_external_members, uniq_internal_members = get_all_members(data)

          ############## Needs to be called in order -> Account (Contacts), User, Project ##########

	        # Create Accounts and Contacts
	       	Account.create_from_clusters(uniq_external_members, user.id, user.organization.id)

	       	# Create internal users
	       	User.create_from_clusters(uniq_internal_members, user.id, user.organization.id)

	       	# Create Projects
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
        else
          format.json { render json: 'Clusters created for user ' + user.email, status: 200}
        end
  		elsif user.nil?
  			format.json { render json: 'User not found.', status: 500}
  			logger.error "ERROR: User not found: " + params[:user_id]
  		elsif data.nil?
  			format.json { render json: 'No data.', status: 200}

  			if params["errors"].nil? # no errors
	  			logger.error "No data return for user: " + params[:user_id]
	  		else # returns error
	  			logger.error "ERROR: Code: " + params[:code].to_s + " Error: " + params["message"]
	  			if params["message"] == "Invalid Credentials"
	  				logger.error "Token might have expired."
	  			end
	  		end
  		end
  	end
	end
end