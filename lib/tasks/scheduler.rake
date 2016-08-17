desc "Heroku scheduler tasks for periodically retrieving latest emails"
namespace :projects do
	
	desc 'Retrieve latest 300 emails for all projects in all organization'
	task load_emails: :environment do
    puts "\n\n=====Task (load_emails) started at #{Time.now}====="

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
	task load_emails_since_yesterday: :environment do
    if [0,6,12,18].include?(Time.now.hour) # Runs once every 6 hours
    	puts "\n\n=====Task (load_emails_since_yesterday) started at #{Time.now}====="
	    after = Time.now.to_i - 86400

	    Organization.all.each do |org|
	    	org.accounts.each do |acc| 
		    	acc.projects.each do |proj|
		    		puts "Org: " + org.name + ", Account: " + acc.name + ", Project: " + proj.name
		    		ContextsmithService.load_emails_from_backend(proj, nil, 60)
		    		sleep(1)
		    	end
		    end
	    end

	  end
	end

	desc 'Retrieve latest 1000 calendar events for all projects in all organization'
	task load_events: :environment do
    puts "\n\n=====Task (load_events) started at #{Time.now}====="

    Organization.all.each do |org|
    	org.accounts.each do |acc| 
	    	acc.projects.each do |proj|
	    		puts "Loading project...\nOrg: " + org.name + ", Account: " + acc.name + ", Project " + proj.name
	    		ContextsmithService.load_calendar_from_backend(proj, Time.current.to_i, 1.month.ago.to_i, 1000)
	    		sleep(1)
	    	end
	    end
    end
	end

	desc 'Retrieve latest calendar events since yesterday for all projects in all organization'
	task load_events_since_yesterday: :environment do
    if [3,9,15,21].include?(Time.now.hour) # Runs once every 6 hours
    	puts "\n\n=====Task (load_events_since_yesterday) started at #{Time.now}====="
	    after = Time.now.to_i - 86400

	    Organization.all.each do |org|
	    	org.accounts.each do |acc| 
		    	acc.projects.each do |proj|
		    		puts "Org: " + org.name + ", Account: " + acc.name + ", Project: " + proj.name
		    		ContextsmithService.load_calendar_from_backend(proj, Time.current.to_i, 1.day.ago.to_i)
		    		sleep(1)
		    	end
		    end
	    end

	  end
	end

	desc 'Email daily project updates on weekdays'
	task :email_daily_summary, [:test] => :environment do |t, args|
		puts "\n\n=====Task (email_daily_summary) started at #{Time.now}====="

		args.with_defaults(:test => false)
		Organization.all.each do |org|
			org.users.each do |usr|
				Time.use_zone(usr.time_zone) do
					if Time.current.hour == 5 && Time.current.wday.between?(1, 5) || (args[:test] && !Rails.env.production?) # In the hour of 5am on weekdays
						puts "Emailing #{usr.email}..."
						UserMailer.daily_summary_email(usr).deliver_later
						sleep(1)
					end
				end
			end
		end
	end

	desc 'Get weekly last touch opportunities'
	task last_touch_weekly: :environment do
		puts "\n\n=====Task (last_touch_weekly) started at #{Time.now}====="

		if Time.now.sunday?
    	Notification.load_opportunity_for_stale_projects
    end
	end

	desc 'Email weekly task summary on Sundays'
	task :email_weekly_summary, [:test] => [:environment] do |t, args|
		puts "\n\n=====Task (email_weekly_summary) started at #{Time.now}====="

		args.with_defaults(:test => false)
		Organization.all.each do |org|
			org.users.each do |usr|
				Time.use_zone(usr.time_zone) do
					if Time.current.sunday? || (args[:test] && !Rails.env.production?) # In the hour of 5pm on Sundays
						puts "Emailing #{usr.email}..."
						UserMailer.weekly_summary_email(usr).deliver_later
						sleep(0.5)
					end
				end
			end
		end
	end

	desc 'Subscribe internal project members who are not already subscribed'
	task subscribe_project_members: :environment do
		puts "\n\n=====Task (subscribe_project_members) started at #{Time.now}====="

		Project.all.each do |proj|
		  subs = proj.subscribers
		  proj.users.registered.onboarded.each do |member|
		    ProjectSubscriber.create(user_id: member.id, project_id: proj.id) if !subs.any? {|s| s.user_id == member.id }
		  end
		end
	end

end