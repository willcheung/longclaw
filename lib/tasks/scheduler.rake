desc "Heroku scheduler tasks for periodically retrieving latest emails"
namespace :projects do
	
	desc 'Retrieve latest 300 emails for all projects in all organization'
	task load_activities: :environment do
    puts "\n\n=====Task (load_activities) started at #{Time.now}====="

    Organization.all.each do |org|
    	org.accounts.each do |acc| 
	    	acc.projects.each do |proj|
	    		puts "Loading project...\nOrg: " + org.name + ", Account: " + acc.name + ", Project " + proj.name
	    		ContextsmithService.load_emails_from_backend(proj, nil, 300)
	    		sleep(1)
	    	end
	    end
    end
	end

	desc 'Retrieve latest emails since yesterday for all projects in all organization'
	task load_activities_since_yesterday: :environment do
    if Time.now.hour.even? # Runs once every 2 hours
    	puts "\n\n=====Task (load_activites_since_yesterday) started at #{Time.now}====="
	    after = Time.now.to_i - 86400

	    Organization.all.each do |org|
	    	org.accounts.each do |acc| 
		    	acc.projects.each do |proj|
		    		puts "Org: " + org.name + ", Account: " + acc.name + ", Project: " + proj.name
		    		ContextsmithService.load_emails_from_backend(proj, after)
		    		sleep(1)
		    	end
		    end
	    end

	  end
	end

	desc 'Email daily project updates'
	task email_daily_summary: :environment do
		puts "\n\n=====Task (email_daily_summary) started at #{Time.now}====="

		Organization.all.each do |org|
			org.users.each do |usr|
				Time.use_zone(usr.time_zone) do
					if Time.current.hour == 5 # In the hour of 5am
						puts "Emailing #{usr.email}..."
						UserMailer.daily_summary_email(usr).deliver_later
						sleep(0.5)
					end
				end
			end
		end
	end
end