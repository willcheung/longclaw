class ExtensionController < ApplicationController
  NUM_ACCOUNT_CONTACT_SHOW_LIMIT = 10  # How many Account Contacts to show
  
  layout "extension", except: [:test, :new]

  before_action :set_salesforce_user
  # before_action :set_account_and_project, only: [:alerts_tasks, :contacts, :metrics]
  before_action :set_account_and_project_for_people, only: [:account]
  # before_action :set_sfdc_status_and_accounts, only: [:alerts_tasks, :contacts, :metrics]
  before_action :get_account_types, only: :no_account
  # before_action :get_current_org_users, only: :alerts_tasks

  def test
    render layout: "empty"
  end

  def index
    # gmail extension provided an email address of the currently logged in user
    @gmail_user = params[:email] ? params[:email] : nil
    render layout: "empty"
  end

  def new
    # render a copy of the devise/sessions.new page that opens Google Account Chooser as a popup
    # store "/extension" as return location for when OmniauthCallbacksController#google_oauth2 calls sign_in_and_redirect
    store_location_for(:user, extension_path(login: true))
    render layout: "empty"
  end

  def no_account
    @domain = URI.unescape(params[:domain], '%2E')
    @account = Account.new
  end

  def project_error
  end

  def private_domain
    @users = []
    new_internal_users = []

    params[:internal].each do |key, u|
      full_name = u[0]
      email = u[1] 
      user = User.find_by_email(email)
      if user.present?
        @users << user
      else
        new_internal_users << {full_name: full_name, email: email}
      end
    end if params[:internal].present?

    # Create previously unidentified internal members as new Users
    @users.concat create_and_return_internal_users(new_internal_users)
  end

  # TODO: Rename this to "People" .html and path
  def account
    @SOCIAL_BIO_TEXT_LENGTH_MAX = 192
    @EMAIL_SUBJECT_TEXT_LENGTH_MAX = 65
    @NUM_LATEST_TRACKED_EMAIL_ACTIVITY_LIMIT = 8 # Number of newest tracked email activities shown in timeline
    @widecaret = "⌃" # 'wider' than standard, from:  / "\u2303".encode('utf-8')

    external_emails = params[:external].present? ? params[:external].values.map{|p| p.second.downcase} : []
    internal_emails = params[:internal].present? ? params[:internal].values.map{|p| p.second.downcase} : []
    account_contacts_emails = (@account.present? && @account.contacts.present?) ? @account.contacts.map{|c| c.email.downcase}.sort : []

    people_emails = external_emails | internal_emails - [current_user.email.downcase]
    account_contacts_emails = (account_contacts_emails - people_emails)[0...NUM_ACCOUNT_CONTACT_SHOW_LIMIT]  # filter by users already in e-mail thread, then truncate list

    @people_with_profile = people_emails.each_with_object([]) { |e, memo| memo << {email: e, profile: Profile.find_or_create_by_email(e)} }
    @account_contacts_with_profile = account_contacts_emails.each_with_object([]) { |e, memo| memo << {email: e, profile: Profile.find_or_create_by_email(e)} }

    people_emails += @account_contacts_with_profile.map{|p| p[:email]}

    # people_emails = ['joe@plugandplaytechcenter.com']
    # people_emails = ['nat.ferrante@451research.com','pauloshan@yahoo.com','sheila.gladhill@browz.com', 'romeo.henry@mondo.com', 'lzion@liveintent.com']
    tracking_requests_this_pastmonth = current_user.tracking_requests.has_any_recipient(people_emails).where(sent_at: 1.month.ago.midnight..Time.current).order("sent_at DESC")
    
    @last_emails_sent_per_person = {}
    @emails_sent_per_person = {}
    emails_uniq_opened_per_person = {}
    emails_total_opened_per_person = {}
    tracking_requests_this_pastmonth.each do |r| 
      people_emails.map do |e|
        if r.recipients.map{ |r| r.downcase }.include? e
          emails_sent = @emails_sent_per_person[e].present? ? @emails_sent_per_person[e] : 0
          emails_sent += 1 

          emails_uniq_opens = emails_uniq_opened_per_person[e].present? ? emails_uniq_opened_per_person[e] : 0
          emails_total_opens = emails_total_opened_per_person[e].present? ? emails_total_opened_per_person[e] : 0

          tracking_events = r.tracking_events.order("date DESC")
          emails_uniq_opens += 1 if tracking_events.limit(1).present?
          emails_total_opens += tracking_events.count

          @emails_sent_per_person[e] = emails_sent
          emails_uniq_opened_per_person[e] = emails_uniq_opens
          emails_total_opened_per_person[e] = emails_total_opens
          
          @last_emails_sent_per_person[e] = [] if @last_emails_sent_per_person[e].blank?
          @last_emails_sent_per_person[e] << { trackingrequest: r, lasttrackingevent: tracking_events.limit(1).present? ? tracking_events.limit(1).first : nil, totaltrackingevents: tracking_events.count } if @last_emails_sent_per_person[e].length < @NUM_LATEST_TRACKED_EMAIL_ACTIVITY_LIMIT
        end
      end # End: people_emails.map do |e|
    end 

    @emails_pct_opened_per_person = {}
    emails_uniq_opened_per_person.each { |e,c| @emails_pct_opened_per_person[e] = c.to_f/@emails_sent_per_person[e].to_f if @emails_sent_per_person[e].present? }
    @emails_engagement_per_person = {}
    emails_total_opened_per_person.each { |e,c| @emails_engagement_per_person[e] = c.to_f/@emails_sent_per_person[e].to_f if @emails_sent_per_person[e].present? }

    # puts "emails_total_opened_per_person: #{emails_total_opened_per_person}"
  end

  def alerts_tasks
    @notifications = @project.notifications.order(:is_complete).take(15)
  end

  def contacts
    @project_members = @project.project_members
    @suggested_members = @project.project_members_all.pending
  end

  def metrics
  end

  def create_account
    @account = Account.new(account_params.merge(
      owner_id: current_user.id, 
      created_by: current_user.id,
      updated_by: current_user.id,
      organization_id: current_user.organization_id,
      status: 'Active')
    )

    respond_to do |format|
      if @account.save
        if create_project
          @project.subscribers.create(user: current_user)
          format.html { redirect_to extension_account_path(internal: params[:internal], external: params[:external]), notice: 'Opportunity was successfully created.' }
          format.js
        else
          format.html { render action: 'no_account' }
          format.js { render json: @project.errors, status: :unprocessable_entity }
        end
      else
        format.html { render action: 'no_account' }
        format.js { render json: @account.errors, status: :unprocessable_entity }
      end
    end
  end

  private

  def set_salesforce_user
    return if @salesforce_user.present? || current_user.nil?

    @salesforce_base_URL = OauthUser.get_salesforce_instance_url(current_user.organization_id)

    if current_user.admin?
      # try to get salesforce production. if not connect, check if it is connected to Salesforce sandbox
      @salesforce_user = OauthUser.find_by(oauth_provider: 'salesforce', organization_id: current_user.organization_id)
      @salesforce_user = OauthUser.find_by(oauth_provider: 'salesforcesandbox', organization_id: current_user.organization_id) if @salesforce_user.nil?
    elsif current_user.power_or_trial_only?  # individual power user or trial/Chrome user
      @salesforce_user = OauthUser.find_by(oauth_provider: 'salesforce', organization_id: current_user.organization_id, user_id: current_user.id)
      #@salesforce_user = OauthUser.find_by(oauth_provider: 'salesforcesandbox', organization_id: current_user.organization_id, user_id: current_user.id) if @salesforce_user.nil?
    end
  end

  # Old before_action helper
  def set_account_and_project
    # p "*** set account and project ***"
    # p params
    ### url example: .../extension/account?internal%5B0%5D%5B%5D=Will%20Cheung&internal%5B0%5D%5B%5D=wcheung%40contextsmith.com&internal%5B1%5D%5B%5D=Kelvin%20Lu&internal%5B1%5D%5B%5D=klu%40contextsmith.com&internal%5B2%5D%5B%5D=Richard%20Wang&internal%5B2%5D%5B%5D=rcwang%40contextsmith.com&internal%5B3%5D%5B%5D=Yu-Yun%20Liu&internal%5B3%5D%5B%5D=liu%40contextsmith.com&external%5B0%5D%5B%5D=Richard%20Wang&external%5B0%5D%5B%5D=rcwang%40enfind.com&external%5B1%5D%5B%5D=Brad%20Barbin&external%5B1%5D%5B%5D=brad%40enfind.com
    ### more readable url example: .../extension/account?internal[0][]=Will Cheung&internal[0][]=wcheung@contextsmith.com&internal[1][]=Kelvin Lu&internal[1][]=klu@contextsmith.com&internal[2][]=Richard Wang&internal[2][]=rcwang@contextsmith.com&internal[3][]=Yu-Yun Liu&internal[3][]=liu@contextsmith.com&external[0][]=Richard Wang&external[0][]=rcwang@enfind.com&external[1][]=Brad Barbin&external[1][]=brad@enfind.com
    ### after Rails parses the params, params[:internal] and params[:external] are both hashes with the structure { "0" => ['Name(?)', 'email@address.com'] }

    # If there are no external users specified, redirect to extension#private_domain page
    redirect_to extension_private_domain_path+"\?"+{ internal: params[:internal] }.to_param and return if params[:external].blank?

    external = params[:external].values.map { |person| person.map { |info| URI.unescape(info, '%2E') } }
    ex_emails = external.map(&:second).reject { |email| get_domain(email).downcase == current_user.organization.domain.downcase || !valid_domain?(get_domain(email)) }

    # if somehow request was made without external people or external people were filtered out due to invalid domain, redirect to extension#private_domain page
    redirect_to extension_private_domain_path+"\?"+{ internal: params[:internal] }.to_param and return if ex_emails.blank? 

    # group by ex_emails by domain frequency, order by most frequent domain
    ex_emails = ex_emails.group_by { |email| get_domain(email) }.values.sort_by(&:size).flatten 
    order_emails_by_domain_freq = ex_emails.map { |email| "email = #{Contact.sanitize(email)} DESC" }.join(',')
    # find all contacts within current_user org that match the external emails, in the order of ex_emails
    contacts = Contact.joins(:account).where(email: ex_emails, accounts: { organization_id: current_user.organization_id}).order(order_emails_by_domain_freq) 
    if contacts.present?
      # get all opportunities that these contacts are members of
      projects = contacts.joins(:visible_projects).includes(:visible_projects).map(&:projects).flatten
      if projects.present?
        # set most frequent project as opportunity
        @project = projects.group_by(&:id).values.max_by(&:size).first
        @account = @project.account
      end
    else
      domains = ex_emails.map { |email| get_domain(email) }.uniq
      where_domain_matches = domains.map { |domain| "email LIKE '%#{domain}'"}.join(" OR ")
      order_domain_frequency = domains.map { |domain| "email LIKE '%#{domain}' DESC"}.join(',')
      # find all contacts within current_user org that have a similar email domain to external emails, in the order of domain frequency
      contacts = Contact.joins(:account).where(accounts: { organization_id: current_user.organization_id }).where(where_domain_matches).order(order_domain_frequency)
      if contacts.blank?
        order_domain_frequency = domains.map { |domain| "domain = '#{domain}' DESC" }.join(',')
        # find all accounts within current_user org whose domain is the email domain for external emails, in the order of domain frequency
        accounts = Account.where(domain: domains, organization: current_user.organization).order(order_domain_frequency)
        # If no accounts are found that match our external email domains at this point, first see if we can match with a SFDC account.  If cannot, redirect to extension#no_account page to allow user to manually create this account.
        if accounts.blank?
          domain = domains.first
          no_account_path = extension_no_account_path(URI.escape(domain, ".")) + "\?" + { internal: params[:internal], external: params[:external] }.to_param  # URL path for the "No Existing Account/Create Account" page 
          
          redirect_to no_account_path and return if !current_user.power_or_trial_only? || @salesforce_user.nil?  # abort if user isn't Power or Trial/Chrome user, or if not connected to SFDC
          
          client = SalesforceService.connect_salesforce(current_user.organization_id)

          sfdc_account_id = find_matching_sfdc_account(client, ex_emails)
          redirect_to no_account_path and return if sfdc_account_id.nil?  # abort if SFDC connection was invalid or SFDC Account link candidate cannot be determined

          # Create a new CS Account and link to the identified SFDC Account
          @account = Account.new(
              name: domain,
              domain: domain,
              owner_id: current_user.id, 
              category: Account::CATEGORY[:Customer],
              created_by: current_user.id,
              updated_by: current_user.id,
              organization_id: current_user.organization_id,
              status: 'Active'
          )

          if !@account.save
            puts "Error creating account!"
            redirect_to no_account_path and return
          else
            # Create an Opportunity for the Account now so that we can add members to it in the next few instructions
            create_project  # uses @account
            @project.subscribers.create(user: current_user)

            sfa = SalesforceAccount.find_by(contextsmith_organization_id: current_user.organization_id, salesforce_account_id: sfdc_account_id)

            if sfa.present?
              puts "Auto-linking SFDC Account '#{sfa.salesforce_account_name}' to new Account '#{domain}'." 
              sfa.account = @account

              SalesforceController.import_sfdc_contacts_and_add_as_members(client: client, account: @account, sfdc_account: sfa) if sfa.save
            end
          end
        else
          @account = accounts.first
        end 
      end # end: if contacts.blank?
    end
    @account ||= contacts.first.account
    @project ||= @account.projects.visible_to(current_user.organization_id, current_user.id).first

    if @project.blank?
      create_project
      @project.subscribers.create(user: current_user)
    elsif params[:action] == "account" 
      # extension always routes to "account" action first, don't need to run create_people for other tabs (contacts or alerts_tasks)
      # since project already exists, any new external members found should be added as suggested members, let user confirm
      create_people
    end
    
    @all_members = @project.users + @project.contacts
    @members = @all_members.first(NUM_ACCOUNT_CONTACT_SHOW_LIMIT) # same value as 

    @clearbit_domain = @account.domain? ? @account.domain : (@account.contacts.present? ? @account.contacts.first.email.split("@").last : "")
  end

  # New before_action helper to be used for new Basic User "People" page.  Matches an account+opportunity (project) with the external contacts in params (i.e., if no external contacts exist, no account or opportunity is returned). 
  # Note: E-mail domains that are typically "invalid" such as "gmail.com", "yahoo.com", "hotmail.com" may be used to identify a "matching" account if we can find the Contact with the e-mail.  Otherwise, we stop and do not attempt to identify a matching account using "invalid" domains, because these domains are too general and can easily match the wrong account.
  def set_account_and_project_for_people
    return if params[:external].blank?

    external = params[:external].values.map { |person| [person.first,person.second.downcase].map { |info| URI.unescape(info, '%2E') } }
    ex_emails = external.map(&:second)

    # ex_emails = ["nat.ferrante@451research.com","pauloshan@yahoo.com","sheila.gladhill@browz.com", "romeo.henry@mondo.com", "lzion@liveintent.com","invalid'o@gmail.com"]
    # group by ex_emails by domain frequency, order by most frequent domain
    ex_emails = ex_emails.group_by { |email| get_domain(email) }.values.sort_by(&:size).flatten 
    order_emails_by_domain_freq = ex_emails.map { |email| "email = #{Contact.sanitize(email)} DESC" }.join(',')
    # find all contacts within current_user org that match the external emails, in the order of ex_emails
    contacts = Contact.joins(:account).where(email: ex_emails, accounts: { organization_id: current_user.organization_id }).order(order_emails_by_domain_freq) 

    if contacts.present?
      # get all opportunities that these contacts are members of
      projects = contacts.joins(:visible_projects).includes(:visible_projects).map(&:projects).flatten

      if projects.present?
        # set most frequent project as opportunity
        @project = projects.group_by(&:id).values.max_by(&:size).first

        @account = @project.account
      end
    else
      ex_emails = ex_emails.reject { |email| get_domain(email).downcase == current_user.organization.domain.downcase || !valid_domain?(get_domain(email)) } # remove e-mails with domains that are too general

      return if ex_emails.blank?  # quit if no "valid" e-mails remain

      domains = ex_emails.map { |email| get_domain(email) }.uniq
      where_domain_matches = domains.map { |domain| "email LIKE '%#{domain}'"}.join(" OR ")
      order_domain_frequency = domains.map { |domain| "email LIKE '%#{domain}' DESC"}.join(',')
      # find all contacts within current_user org that have a similar email domain to external emails, in the order of domain frequency
      contacts = Contact.joins(:account).where(accounts: { organization_id: current_user.organization_id }).where(where_domain_matches).order(order_domain_frequency)
      # puts "contacts:"
      # contacts.each {|c| puts "contact: #{c.email}" }
      if contacts.blank?
        order_domain_frequency = domains.map { |domain| "domain = '#{domain}' DESC" }.join(',')
        # find all accounts within current_user org whose domain is the email domain for external emails, in the order of domain frequency
        accounts = Account.where(domain: domains, organization: current_user.organization).order(order_domain_frequency)
        # If no accounts are found that match our external email domains at this point stop (don't create a new account)
        return if accounts.blank?
          
        @account = accounts.first
      end # end: if contacts.blank?
    end
    @account ||= contacts.first.account
    @project ||= @account.projects.visible_to(current_user.organization_id, current_user.id).first
  end

  # Find and return the external sfdc_id of the most likely SFDC Account given an array of contact emails; returns nil if one cannot be determined.
  def find_matching_sfdc_account(client, emails=[])

    return nil if client.nil? || emails.blank?  # abort if connection invalid or no emails passed

    # client = SalesforceService.connect_salesforce(current_user.organization_id) # not necessary to reconnect!!
    query_statement = "SELECT AccountId, Email FROM Contact WHERE not(Email = null OR AccountId = null) GROUP BY AccountId, Email ORDER BY AccountId, Email" # Use GROUP BY as a workaround to get Salesforce to SELECT distinct AccountID's and Email's
    sfdc_contacts_results = SalesforceService.query_salesforce(client, query_statement)

    return nil if sfdc_contacts_results[:status] == "ERROR" || sfdc_contacts_results[:result].length == 0 # abort if SFDC query error or if no contacts were found

    contacts_with_accounts = sfdc_contacts_results[:result].map { |r| [r[:AccountId],r[:Email]] }

    return if contacts_with_accounts.nil?

    #### Match SFDC Account by contact email
    print "Attempting to match contacts by email..."  

    contacts_by_account_h = contacts_with_accounts.each_with_object(Hash.new(Array.new)) { |p, memo| memo[p[0]] += [p[1]] }  # obtain a hash of contact emails with AccountId as the keys

    account_contact_matches_by_email = Hash.new(0)
    emails.each do |e| 
      contacts_by_account_h.each { |account, contacts| account_contact_matches_by_email[account] += 1 if contacts.include? (e) }
    end

    account_contact_matches_by_email = account_contact_matches_by_email.to_a.sort_by {|r| r[1]}.reverse  # sort by most-frequent first
    #puts "Email matches by account: #{account_contact_matches_by_email}" 
    if account_contact_matches_by_email.empty?
      #puts "No match!"  # continue with domain matching
    elsif account_contact_matches_by_email.length == 1 || account_contact_matches_by_email.first[1] != account_contact_matches_by_email.second[1]
      puts "SFDC account match was found! " + account_contact_matches_by_email.first[0]
      return account_contact_matches_by_email.first[0]
    else
      #puts "Ambiguous, because tied!"  # continue with domain matching
    end

    #### Match SFDC Account by contact email domains
    print "unsuccessful. Trying to match contacts by domain..."
    
    domains = emails.map {|e| get_domain(e)}
    domains = domains.each_with_object(Hash.new(0)) { |d, memo| memo[d] += 1 }

    accounts_by_contact_domain_h = contacts_with_accounts.each_with_object({}) do |cp, memo|
      c_account = cp[0]
      c_domain = get_domain(cp[1])
      if memo[c_domain].nil? 
        memo[c_domain] = {c_account => 1}
      else
        memo[c_domain][c_account] = memo[c_domain][c_account].nil? ? 1 : memo[c_domain][c_account] + 1
      end
    end # obtain a hash of another hash (AccountId's with the total occurence of domains found in contact emails) with domains as the keys. 
    # e.g.,:  { "aol.com"   => {"AccountA"=>1, "AccountC"=>2}, 
    #           "apple.com" => {"AccountA"=>1},
    #           "gmail.com" => {"AccountB"=>1} }
    #puts "accounts_by_contact_domain: #{accounts_by_contact_domain_h}"

    account_wt_match_score_by_domain = {}
    domains.each do |d,dc| 
      #puts "domain=#{d}, count=#{dc}"
      #puts "accounts_by_contact_domain_h[d]=#{accounts_by_contact_domain_h[d]}"
      accounts_by_contact_domain_h[d].each do |h|
        #print "\t h: #{h}  "
        account = h[0]
        account_wt_match_score_by_domain[account] = dc * h[1] + (account_wt_match_score_by_domain[account].nil? ? 0 : account_wt_match_score_by_domain[account])
        #puts "\t account_wt_match_score_by_domain: #{account_wt_match_score_by_domain}"
      end if accounts_by_contact_domain_h[d].present?
    end

    account_wt_match_score_by_domain = account_wt_match_score_by_domain.to_a.sort_by {|r| r[1]}.reverse  # sort by most-frequent first
    #puts "account_wt_match_score_by_domain: #{account_wt_match_score_by_domain}"
    if account_wt_match_score_by_domain.empty?
      # puts "Still no match!"  # match unsuccessful
    elsif account_wt_match_score_by_domain.length == 1 || account_wt_match_score_by_domain.first[1] != account_wt_match_score_by_domain.second[1]
      # puts "SFDC account match was found! " + account_wt_match_score_by_domain.first[0]
      return account_wt_match_score_by_domain.first[0]
    else
      # puts "Still tied!"  # match unsuccessful
    end
    # puts "Unsuccessful. No SFDC Accounts were found to unambiguously match these contacts during search!"
    nil
  end

  def get_account_types
    custom_lists = current_user.organization.get_custom_lists_with_options
    @account_types = !custom_lists.blank? ? custom_lists["Account Type"] : {}
  end

  # Set the various status flags and complete operations related to SFDC and linked SFDC entity
  # def set_sfdc_status_and_accounts
  #   @sfdc_accounts_exist = current_user.organization.salesforce_accounts.limit(1).present?
  #   @linked_to_sfdc = @project && (!@project.salesforce_opportunity.nil? || @project.account.salesforce_accounts.present?)
  #   @enable_sfdc_login_and_linking = current_user.admin? || current_user.power_or_trial_only?
  #   @enable_sfdc_refresh = @enable_sfdc_login_and_linking  # refresh and login/linking permissions can be separate in the future

  #   # If no SFDC accounts found, automatically refresh the SFDC accounts list
  #   if !@sfdc_accounts_exist && @enable_sfdc_login_and_linking
  #     SalesforceAccount.load_accounts(current_user.organization_id) 
  #     @sfdc_accounts_exist = true
  #   end
  # end

  def create_project
    # p "*** creating project for account #{@account.name} ***"
    @project = @account.projects.new(
      name: @account.name,
      description: "Default opportunity for #{@account.name}",
      created_by: current_user.id,
      updated_by: current_user.id,
      owner_id: current_user.id,
      is_confirmed: true,
    )
    @project.project_members.new(user: current_user)

    # new project needs some initial external people, add them as confirmed members before loading emails/calendar from backend
    create_people(ProjectMember::STATUS[:Confirmed])

    success = @project.save
    if success
      ContextsmithService.load_emails_from_backend(@project, 2000)
      ContextsmithService.load_calendar_from_backend(@project, 1000)
    else
      redirect_to extension_project_error_path and return
    end
    success
  end

  # Helper method for creating people, used in set_account_and_project & create_project (@project should already be set before calling this)
  # By default, all internal people are added to @project as confirmed members, all external people are added to @project as suggested members
  def create_people(status=ProjectMember::STATUS[:Pending])
    if params[:internal].present?
      internal = params[:internal].values.map { |person| person.map { |info| URI.unescape(info, '%2E') } } 
      # p "*** creating new internal members for project #{@project.name} ***"
      internal.select { |person| get_domain(person[1]) == current_user.organization.domain }.each do |person|
        unless person[0] == 'me' || person[1] == current_user.email
          user = current_user.organization.users.create_with(
            first_name: get_first_name(person[0]),
            last_name: get_last_name(person[0]),
            invited_by_id: current_user.id,
            invitation_created_at: Time.current
          ).find_or_create_by(email: person[1])

          ProjectMember.create(project: @project, user: user)
        end
      end 
    end

    external = params[:external].present? ? params[:external].values.map { |person| [person.first, person.second.downcase].map { |info| URI.unescape(info, '%2E') } } : []
    # p "*** creating new external members for project #{@project.name} ***"
    external.reject { |person| get_domain(person[1]) == current_user.organization.domain || !valid_domain?(get_domain(person[1])) }.each do |person|
      Contact.find_or_create_from_email_info(person[1], person[0], @project, status, "Chrome")
    end
  end

  # Parameters:  internal_members_a - An array of hashes {full_name: full_name, email: email} to indicate potential new users
  def create_and_return_internal_users(internal_members_a)
    new_users = []
    #puts "internal_members_a: #{internal_members_a}"
    internal_members_a.each do |u|
      next if User.find_by_email(u[:email]).present?

      name = u[:full_name].split(" ")
      first_name = name[0].nil? ? '' : name[0]
      last_name = name[1].nil? ? '' : name[1]
      u = User.create(
        first_name:  first_name,
        last_name:  last_name,
        email:  u[:email],
        organization_id:  current_user.organization_id,
        invited_by_id:  current_user.id,
        invitation_created_at:  Time.current
      )
      new_users << u
    end
    new_users
  end

  # Never trust parameters from the scary internet, only allow the white list through.
  def account_params
    params.require(:account).permit(:name, :website, :phone, :description, :address, :category, :domain)
  end
end
