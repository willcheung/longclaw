desc "Heroku scheduler tasks for periodically retrieving latest emails"
namespace :projects do
	
	desc 'Retrieve latest 100 emails for all projects in all organization'
	task load_activities: :environment do
    puts "\n\n=====Task (load_activities) started at #{Time.now}====="

    Organization.all.each do |org|
    	org.accounts.each do |acc| 
	    	acc.projects.each do |proj|
	    		puts "Org: " + org.name + ", Account: " + acc.name + ", Project " + proj.name
	    		ContextsmithService.load_emails_from_backend(proj)
	    	end
	    end
    end
	end

	desc 'Retrieve latest emails since yesterday for all projects in all organization'
	task load_activities_since_yesterday: :environment do
    puts "\n\n=====Task (load_activites_since_yesterday) started at #{Time.now}====="

    after = Time.now.to_i - 86400

    Organization.all.each do |org|
    	org.accounts.each do |acc| 
	    	acc.projects.each do |proj|
	    		puts "Org: " + org.name + ", Account: " + acc.name + ", Project " + proj.name
	    		ContextsmithService.load_emails_from_backend(proj, after)
	    	end
	    end
    end
	end

	desc 'Email daily project updates'
	task email_daily_summary: :environment do
		puts "\n\n=====Task (email_daily_summary) started at #{Time.now}====="

		Organization.all.each do |org|
			org.users.registered.each do |usr|
				puts "Emailing #{usr.email}..."
				UserMailer.daily_summary_email(usr).deliver_later
			end
		end
	end
end