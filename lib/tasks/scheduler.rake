desc "Heroku scheduler tasks for periodically retrieving latest e-mails"
namespace :scheduler do
    
    desc 'Retrieve latest 300 e-mails for all active and confirmed projects in all organizations'
    task load_emails: :environment do
        puts "\n\n=====Task (load_emails) started at #{Time.now}====="

        Organization.is_active.each do |org|
            org.accounts.each do |acc| 
                acc.projects.is_active.each do |proj|
                    puts "Loading project...\nOrg: " + org.name + ", Account: " + acc.name + ", Project " + proj.name
                    ContextsmithService.load_emails_from_backend(proj, 300)
                    sleep(1)
                end
            end
        end
    end

    desc 'Retrieve latest 300 e-mails for specific active and confirmed projects in organizations'
    task load_emails_for_org: :environment do
      # Parameters: organization_id (via variable name injection into Environment)
      # Usage: rake scheduler:load_emails_for_org org=organization_uuid 
        puts "\n\n=====Task (load_emails_for_org) started at #{Time.now}====="
        if ENV['org'].nil?
            puts "*** Usage: rake scheduler:load_emails_for_org org=organization_uuid ***\n\n"
        else
          org = Organization.find(ENV['org']) 
            org.accounts.each do |acc| 
              acc.projects.is_active.each do |proj|
                  puts "Loading project...\nOrg: " + org.name + ", Account: " + acc.name + ", Project " + proj.name
                  ContextsmithService.load_emails_from_backend(proj, 300)
                  sleep(1)
              end
            end
        end
    end


    desc 'Retrieve latest e-mails since yesterday for all active and confirmed projects in all organizations'
    task load_emails_since_yesterday: :environment do
        # Runs once every ~6 hours, except during business hours on East Coast and West Coast, U.S. when it runs every 2 hours. (9AM EST -> 5PM PDT(daylight savings) = 13:00-01:00 UTC)
        if ( ((Time.now.saturday? || Time.now.sunday?) && [0,6,12,18].include?(Time.now.hour)) || (!(Time.now.saturday? || Time.now.sunday?) && [1,7,13,15,17,19,21,23].include?(Time.now.hour)) )
            puts "\n\n=====Task (load_emails_since_yesterday) started at #{Time.now}====="

            uri = URI(ENV['BASE_URL'] + '/hooks/load_emails_since_yesterday')
            req = Net::HTTP::Post.new(uri)
            res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") { |http| http.request(req) }
        end
    end

    desc 'Retrieve latest 300 calendar events for all active and confirmed projects in all organizations'
    task load_events: :environment do
        puts "\n\n=====Task (load_events) started at #{Time.now}====="

        Organization.is_active.each do |org|
            org.accounts.each do |acc| 
                acc.projects.is_active.each do |proj|
                    puts "Loading project...\nOrg: " + org.name + ", Account: " + acc.name + ", Project/Stream: " + proj.name
                    ContextsmithService.load_calendar_from_backend(proj, 300)
                    sleep(1)
                end
            end
        end
    end

    desc 'Retrieve latest calendar events since yesterday for all active and confirmed projects in all organizations'
    task load_events_since_yesterday: :environment do
        # Runs once every ~6 hours, except during business hours on East Coast and West Coast, U.S. when it runs every 2 hours. (9AM EST -> 5PM PDT(daylight savings) = 13:00-01:00 UTC)
        if ( ((Time.now.saturday? || Time.now.sunday?) && [3,9,15,21].include?(Time.now.hour)) || (!(Time.now.saturday? || Time.now.sunday?) && [1,7,13,15,17,19,21,23].include?(Time.now.hour)) )
            puts "\n\n=====Task (load_events_since_yesterday) started at #{Time.now}====="

            uri = URI(ENV['BASE_URL'] + '/hooks/load_events_since_yesterday')
            req = Net::HTTP::Post.new(uri)
            res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") { |http| http.request(req) }
        end
    end

    desc 'Email daily project updates on weekdays'
    task :email_daily_summary, [:test] => :environment do |t, args|
        puts "\n\n=====Task (email_daily_summary) started at #{Time.now}====="

        args.with_defaults(:test => false)
        Organization.is_active.each do |org|
            org.users.not_disabled.each do |usr|
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
        Organization.is_active.each do |org|
            Notification.load_alert_for_days_inactive(org)
        end
    end

    desc 'Email weekly task summary on Sundays'
    task :email_weekly_summary, [:test] => :environment do |t, args|
        puts "\n\n=====Task (email_weekly_summary) started at #{Time.now}====="

        args.with_defaults(:test => false)
        Organization.is_active.each do |org|
            org.users.not_disabled.each do |usr|
                Time.use_zone(usr.time_zone) do
                    if Time.current.hour == 17 && Time.current.sunday? || (args[:test] && !Rails.env.production?) # In the hour of 5pm on Sundays
                        UserMailer.weekly_summary_email(usr).deliver_later
                        sleep(0.5)
                        #puts "user=#{ get_full_name(usr) }"
                        #puts "   Time.current.hour=#{ Time.current.hour } (17? #{ Time.current.hour == 17 })"
                        #puts "   Time.current.sunday?=#{ Time.current.sunday? }"
                        #puts "   args[:test]=#{ args[:test] }"
                        #puts "   Rails.env.production?=#{ Rails.env.production? }"
                    end
                end
            end
        end
    end

    desc 'Email weekly tracking summary on Sundays'
    task :email_weekly_tracking_summary, [:test] => :environment do |t, args|
        puts "\n\n=====Task (email_weekly_tracking_summary) started at #{Time.now}====="

        args.with_defaults(:test => false)
        if (args[:test] || Rails.env.production?)
            Organization.is_active.each do |org|
                org.users.not_disabled.each do |usr|
                    if usr.email_weekly_tracking and usr.oauth_access_token.present?
                        UserMailer.weekly_tracking_summary(usr).deliver_later
                        sleep(0.5)
                    end
                end
            end

            puts "\n\n=====Task (email_weekly_tracking_summary) ended at #{Time.now}====="
        else
            puts "\n\n=====Task (email_weekly_tracking_summary) ended without running at #{Time.now}====="
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
    # Usage: rake scheduler:confirm_projects_for_org org=organization_uuid [step=onboarding_step_min_val] (Note: default STEP=confirm_projects)
    # Utils::ONBOARDING = { "onboarded": -1, "fill_in_info": 0, "tutorial": 1, "confirm_projects": 2 }
    task confirm_projects_for_org: :environment do
        puts "\n\n=====Task (confirm_projects_for_org) started at #{Time.now}====="

        onboarding_step_min = ENV['step'].to_i
        onboarding_step_min = Utils::ONBOARDING[:confirm_projects] if ENV['step'].nil?

        if ENV['org'].nil?
            puts "*** Usage: rake scheduler:confirm_projects_for_org org=organization_uuid [step=onboarding_step_min_val] (Note: default STEP=confirm_projects) ***\n\n"
        else
            org = Organization.find(ENV['org'])
            selected_users = org.users.select { |u| (!(u.onboarding_step.nil? || u.onboarding_step == Utils::ONBOARDING[:onboarded]) && u.onboarding_step >= onboarding_step_min) }
            puts "Running confirm_projects_for_user() for unconfirmed users in organization '#{org.name}' at onboarding_step=#{onboarding_step_min}."
            if selected_users.count == 0
                puts "No selected users."
            else
                puts "Selected users (#{selected_users.count} total):"
            end
            selected_users.each_with_index do |u,i| 
                puts "** #{i+1}. #{get_full_name(u)} {updated_at: #{u.updated_at}, onboarding_step: #{u.onboarding_step}} **"
                User.confirm_projects_for_user(u) 
            end
        end
    end

    desc 'Keep all activities in demo Project up to date'
    # Optional Parameters: project_id (via variable name injection into environment)
    # Usage: rake scheduler:time_jump_demo proj=project_uuid (id of Stark Industries in production=502b8160-0536-48da-9021-1561b957434e)
    task time_jump_demo: :environment do
        puts "\n\n=====Task (time_jump_demo) started at #{Time.now}====="
        if ENV['proj'].nil?
            puts "No proj id provided, exiting... (*** Usage: rake scheduler:time_jump_demo proj=project_uuid ***)"
        else
            begin
                p = Project.find(ENV['proj'])
                p.time_jump 3.hours.ago
                puts "time_jumped all activities in #{p.name}(id=#{ENV['proj']}) to a recent date for demos"
            rescue ActiveRecord::RecordNotFound
                puts "*** CAUTION: demo Project with id=#{ENV['proj']} to time_jump could not be found, exiting... ***"
            end
        end
    end

    desc 'Refresh Salesforce data for each Salesforce user'
    # Refreshes list of accounts and opportunities appropriate for each SFDC user.  This will also create opps/accts for new opportunities, update values in mapped (standard and custom) fields, sync SFDC activities for linked CS opps, and import/upsert SFDC contacts for linked CS accts.
    # Usage: rake scheduler:refresh_salesforce
    task refresh_salesforce: :environment do
        puts "\n\n=====Task (refresh_salesforce) started at #{Time.now}====="
        sfdc_refresh_configs = CustomConfiguration.where("config_type = :config_type AND ((config_value::jsonb)->>'scheduled_sync')::jsonb ?| array[:keys]", config_type: CustomConfiguration::CONFIG_TYPE[:Salesforce_sync], keys: CustomConfiguration::PERIOD_TYPE.keys)
        sfdc_refresh_configs.each do |cf|
            refresh_period = nil
            cf.config_value["scheduled_sync"].keys.each do |per|
                refresh_period = per if (CustomConfiguration::PERIOD_TYPE.keys.include? per) && cf.config_value["scheduled_sync"][per]["next_run"].blank? || DateTime.parse(cf.config_value["scheduled_sync"][per]["next_run"]) <= Time.now  # if "next_run" is an empty string then refresh is enabled but never been run (simply awaiting update upon the first run).
            end

            next if refresh_period.blank? # could not find any scheduled refreshes that are due now

            sfdc_client = nil
            if cf.user_id.present?
                begin
                    user = User.find(cf.user_id)
                rescue ActiveRecord::RecordNotFound
                    puts "\n**** scheduler:refresh_salesforce SFDC error **** Cannot refresh Salesforce data for user '#{cf.user_id}', because this User cannot be found!"
                    next
                else
                    sfdc_client = SalesforceService.connect_salesforce(user: user) 
                end
            else
                organization = Organization.find(cf.organization_id)
                sfdc_client = SalesforceService.connect_salesforce(organization: organization) 
            end

            if sfdc_client.present?
                puts "\n[ scheduler:refresh_salesforce ] - Refreshing Salesforce for Organization=#{cf.organization.name} User=#{user.present? && !user.admin? ? user.email : "Admin user"} (frequency=#{refresh_period}, last_successful_run='#{cf.config_value["scheduled_sync"][refresh_period]["last_successful_run"].present? ? cf.config_value["scheduled_sync"][refresh_period]["last_successful_run"] : "never" }')."
                # SalesforceAccount.load_accounts(sfdc_client, (user.organization_id if user.present?) || organization.id)
                if user.present?
                    SalesforceController.import_and_create_contextsmith(client: sfdc_client, user: user, for_periodic_refresh: true)
                else # organization.present?
                    admin_user = organization.users.find{|u| u.admin?} # select any to use
                    SalesforceController.import_and_create_contextsmith(client: sfdc_client, user: admin_user, for_periodic_refresh: true) if admin_user.present?
                end

                # update scheduled_sync timestamp upon successful completion
                cf = CustomConfiguration.find(cf.id)  # get updated copy to avoid overwriting timestamps set during refresh!
                now_ts = Time.now
                cf.config_value["scheduled_sync"][refresh_period]["last_successful_run"] = now_ts
                cf.config_value["scheduled_sync"][refresh_period]["next_run"] = (cf.config_value["scheduled_sync"][refresh_period]["next_run"].blank? ? now_ts : DateTime.parse(cf.config_value["scheduled_sync"][refresh_period]["next_run"])) + CustomConfiguration::PERIOD_TYPE[refresh_period][:time_value]
                cf.save
            else
                puts "\n**** scheduler:refresh_salesforce SFDC error **** Cannot establish a Salesforce connection for Organization=#{cf.organization.name} User=#{user.present? && !user.admin? ? user.email : "Admin user"}!"
            end
        end
        puts "\n\n=====Task (refresh_salesforce) completed at #{Time.now}====="
    end
end
