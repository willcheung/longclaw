desc "Heroku scheduler tasks for periodically retrieving latest emails"
namespace :projects do
	
	desc 'Retrieve latest 100 emails for all projects in all organization'
	task load_activities: :environment do
    start_time = Time.now
    puts "\n\n=====Task started at #{start_time}====="

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
    start_time = Time.now
    puts "\n\n=====Task started at #{start_time}====="

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
end