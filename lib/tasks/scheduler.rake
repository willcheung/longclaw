desc "Heroku scheduler tasks for periodically retrieving latest emails"
namespace :scheduler do
    
    desc 'Retrieve latest 300 emails for all active and confirmed projects in all organizations'
    task load_emails: :environment do
        puts "\n\n=====Task (load_emails) started at #{Time.now}====="

        Organization.all.each do |org|
            org.accounts.each do |acc| 
                acc.projects.is_active.each do |proj|
                    puts "Loading project...\nOrg: " + org.name + ", Account: " + acc.name + ", Project " + proj.name
                    ContextsmithService.load_emails_from_backend(proj, 300)
                    sleep(1)
                end
            end
        end
    end

    desc 'Retrieve latest emails since yesterday for all active and confirmed projects in all organizations'
    task load_emails_since_yesterday: :environment do
        if [0,6,12,18].include?(Time.now.hour) # Runs once every 6 hours
            puts "\n\n=====Task (load_emails_since_yesterday) started at #{Time.now}====="

            Organization.all.each do |org|
                org.accounts.each do |acc| 
                    acc.projects.is_active.each do |proj|
                        puts "Org: " + org.name + ", Account: " + acc.name + ", Project: " + proj.name
                        ContextsmithService.load_emails_from_backend(proj)
                        sleep(1)
                    end
                end
            end
        end
    end

    desc 'Retrieve latest 300 calendar events for all active and confirmed projects in all organizations'
    task load_events: :environment do
        puts "\n\n=====Task (load_events) started at #{Time.now}====="

        Organization.all.each do |org|
            org.accounts.each do |acc| 
                acc.projects.is_active.each do |proj|
                    puts "Loading project...\nOrg: " + org.name + ", Account: " + acc.name + ", Project " + proj.name
                    ContextsmithService.load_calendar_from_backend(proj, 300)
                    sleep(1)
                end
            end
        end
    end

    desc 'Retrieve latest calendar events since yesterday for all active and confirmed projects in all organizations'
    task load_events_since_yesterday: :environment do
        if [3,9,15,21].include?(Time.now.hour) # Runs once every 6 hours
            puts "\n\n=====Task (load_events_since_yesterday) started at #{Time.now}====="

            Organization.all.each do |org|
                org.accounts.each do |acc| 
                    acc.projects.is_active.each do |proj|
                        puts "Org: " + org.name + ", Account: " + acc.name + ", Project: " + proj.name
                        ContextsmithService.load_calendar_from_backend(proj, 100, 1.day.ago.to_i)
                        sleep(1)
                    end
                end
            end
        end
    end

    desc 'Retrieve latest BaseCamp2 Events for all projects in all organization'
    task load_basecamp2_events: :environment do
        if [0,6,12,18].include?(Time.now.hour) # Runs once every 6 hours
            puts "\n\n=====Task (load_basecamp2_eventsload_basecamp2_events) started at #{Time.now}====="

            Organization.all.each do |org|
                org.oauth_users.basecamp_user.each do |user| 
                    user.integrations.each do |integ|
                        BasecampService.load_basecamp2_events_from_backend(user, integ)
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
                    if Time.current.hour == 5 && Time.current.wday.between?(2, 6) || (args[:test] && !Rails.env.production?) # 5am next day after a weekday
                        UserMailer.daily_summary_email(usr).deliver_later
                        sleep(1)
                    end
                end
            end
        end
    end

    desc 'Generate Days Inactive alerts'
    task alert_for_days_inactive: :environment do
        puts "\n\n=====Task (alert_for_days_inactive) started at #{Time.now}====="
        Organization.all.each do |org|
            Notification.load_alert_for_days_inactive(org)
        end
    end

    desc 'Email weekly task summary on Sundays'
    task :email_weekly_summary, [:test] => :environment do |t, args|
        puts "\n\n=====Task (email_weekly_summary) started at #{Time.now}====="

        args.with_defaults(:test => false)
        Organization.all.each do |org|
            org.users.each do |usr|
                Time.use_zone(usr.time_zone) do
                    if Time.current.hour == 17 && Time.current.sunday? || (args[:test] && !Rails.env.production?) # In the hour of 5pm on Sundays
                        UserMailer.weekly_summary_email(usr).deliver_later
                        sleep(0.5)
                        print "user=", get_full_name(usr), "\n"
                        print "   Time.current.hour=", Time.current.hour, " (17? ", Time.current.hour == 17, ")\n"
                        print "   Time.current.sunday?=", Time.current.sunday?, "\n"
                        print "   args[:test]=", args[:test], "\n"
                        print "   Rails.env.production?=", Rails.env.production?, "\n"
                    end
                end
            end
        end
    end

    desc 'Subscribe internal project members who are not already subscribed'
    task subscribe_project_members: :environment do
        puts "\n\n=====Task (subscribe_project_members) started at #{Time.now}====="

        Project.all.is_active.is_confirmed.each do |proj|
          subs = proj.subscribers
          proj.users.registered.onboarded.each do |member|
            ProjectSubscriber.create(user_id: member.id, project_id: proj.id) if !subs.any? {|s| s.user_id == member.id }
          end
        end
    end

    desc 'Confirm all projects for non-Onboarded users in an organization'
    # Parameters: organization_id (via variable name injection into Environment)
    # Usage: rake scheduler:confirm_projects_for_org org=organization_uuid [step=<onboarding_step_min_val>]  (Note: default STEP=confirm_projects)
    # Utils::ONBOARDING = { "onboarded": -1, "fill_in_info": 0, "tutorial": 1, "confirm_projects": 2 }
    task confirm_projects_for_org: :environment do
        puts "\n\n=====Task (confirm_projects_for_org) started at #{Time.now}====="

        onboarding_step_min = ENV['step'].to_i
        onboarding_step_min = Utils::ONBOARDING[:confirm_projects] if ENV['step'].nil?

        if ENV['org'].nil?
            puts "*** Usage: rake scheduler:confirm_projects_for_org org=organization_uuid [step=<onboarding_step_min_val>]  (Note: default STEP=confirm_projects) ***\n\n"
        else
            org =  Organization.find(ENV['org'])
            selected_users = org.users.select { |u| (!(u.onboarding_step.nil? or u.onboarding_step == Utils::ONBOARDING[:onboarded]) and u.onboarding_step >= onboarding_step_min) }
            puts "Running confirm_projects_for_user() for unconfirmed users in organization '#{org.name}' at onboarding_step=#{onboarding_step_min}."
            if selected_users.count == 0
                puts "No selected users."
            else
                puts "Selected users (#{selected_users.count} total):"
            end
            selected_users.each_with_index do |u,i| 
                puts "#{i+1}. #{get_full_name(u)} {updated_at: #{u.updated_at}, onboarding_step: #{u.onboarding_step}}"
                User.confirm_projects_for_user(u) 
            end
        end
    end
end