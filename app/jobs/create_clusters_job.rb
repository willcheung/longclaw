class CreateClustersJob < ActiveJob::Base
  queue_as :default

  def perform(params)

    ActiveRecord::Base.connection_pool.with_connection do
      user = User.find_by_id(params[:user_id])
      data = params["_json"]

      if user.blank?
        puts "ERROR (Create Clusters): User not found: " + params[:user_id]
        # ahoy.track("Error Create Cluster", message: "User not found: #{params[:user_id]}")
        # raise "ERROR: User not found during callback: " + params[:user_id]
        return
      elsif data.blank?
        if params['code'] == 401 # Invalid credentials
          puts "ERROR (Create Clusters): Invalid credentials: #{params['message']}\n"
          # ahoy.track("Error Create Cluster for " + params[:user_id], message: "#{params['message']}")
          # raise "ERROR: Invalid credential during callback: " + params[:user_id]
          return
        elsif params['code'] == 404 # No external cluster found
          puts "ERROR (Create Clusters): No external cluster found: #{params['message']}"
          # ahoy.track("Error Create Cluster for " + params[:user_id], message: "#{params['message']}")
          # skip create clusters, but update user and and send welcome email
        end
      elsif !data.kind_of?(Array)
        puts "ERROR (Create Clusters): Unhandled backend response #{params['message']}"
        # ahoy.track("Error Create Cluster for " + params[:user_id], message: "Unhandled backend response #{params['message']}.")
        # raise "ERROR: Unhandled backend response during callback: " + params[:user_id]
        return
      else
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
      end

      # Update flag indicating cluster creation is complete
      if user.cluster_create_date.nil?
        user.update_attributes(cluster_create_date: Time.now, cluster_update_date: Time.now)
      else
        user.update_attributes(cluster_update_date: Time.now)
      end

      # Send welcome e-mail with confirm_projects link
      num_of_projects = Project.where(created_by: user.id, is_confirmed: false).count
      puts "Sending onboarding email to #{user.email}"
      UserMailer.welcome_email(user, num_of_projects, ENV['BASE_URL'] + '/onboarding/confirm_projects').deliver_later
    end

  rescue => e
    puts "ERROR (Create Clusters): Something went wrong: " + e.message
    puts e.backtrace.join("\n")
    # ahoy.track("Error Create Cluster", message: e.message, backtrace: e.backtrace.join("\n"))
  ensure
    # run garbage collection to free up memory when done with create clusters
    GC.start
  end

end

