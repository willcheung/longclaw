require 'google/api_client/client_secrets'
require 'google/apis/gmail_v1'

class ExtensionController < ApplicationController
  Gmail = Google::Apis::GmailV1 # Alias the module
  NUM_ACCOUNT_CONTACT_SHOW_LIMIT = 10  # How many Account Contacts to show
  NUM_PARAM_LIST_LIMIT = 128  # Number of external and internal contacts to limit 
  
  layout "extension", except: [:test, :new]

  before_action :get_google_service, only: [:attachments, :download]
  before_action :filter_params
  before_action :set_salesforce_user
  before_action :set_account_and_project, only: [:account, :salesforce, :company]
  # before_action :get_current_org_opportunity_stages, only: [:salesforce]
  # before_action :get_current_org_opportunity_forecast_categories, only: [:salesforce]
  before_action :get_account_types, only: :no_account
  # before_action :set_account_and_project_old, only: [:alerts_tasks, :contacts, :metrics]
  # before_action :set_sfdc_status_and_accounts, only: [:alerts_tasks, :contacts, :metrics]
  before_action :get_current_org_users, only: :custom_view
  before_action :get_current_org_opportunity_stages, only: :custom_view
  before_action :get_current_org_opportunity_forecast_categories, only: :custom_view

  def test
    render layout: 'empty'
  end

  def share
    referral_code = PlansService.referral_code(current_user)
    @referral_url = url_for(controller: 'extension', action: 'refer') + "?ref=#{referral_code}"

    customer = Stripe::Customer.retrieve(current_user.stripe_customer_id, :expand => 'subscriptions') if current_user.stripe_customer_id.present?
    @months_of_plusplan_earned = (customer.present? && customer.account_balance.present? && customer.account_balance < 0 ? (customer.account_balance).abs/500 : 0)
    render layout: 'empty'
  end

  def refer
    render layout: 'empty'
  end

  def settings
    @ts = get_tracking_setting

    respond_to do |format|
      format.html { render layout: 'empty'}
      format.json { render json: @ts }
    end
  end

  def save_settings
    ts = get_tracking_setting

    if @params[:bcc_email].blank?
      ts.bcc_email = ''
    else
      ts.bcc_email = @params[:bcc_email]
    end
    ts.save
    render layout: 'empty'
  end

  def index
    # gmail extension provided an email address of the currently logged in user
    @gmail_user = @params[:email].present? ? @params[:email] : nil
    render layout: 'empty'
  end

  def new
    # render a copy of the devise/sessions.new page that opens Google Account Chooser as a popup
    # store "/extension" as return location for when OmniauthCallbacksController#google_oauth2 calls sign_in_and_redirect
    store_location_for(:user, extension_path(login: true))
    render layout: 'empty'
  end

  # Note: params[:domain] is unfiltered!
  def no_account
    @domain = URI.unescape(params[:domain], '%2E')
    @account = Account.new
  end

  def project_error
  end

  def private_domain
    @users = []
    new_internal_users = []

    @params[:internal].each do |full_name, email|
      user = User.find_by_email(email)
      if user.present?
        @users << user
      else
        new_internal_users << {full_name: full_name, email: email}
      end
    end if @params[:internal].present?

    # Create previously unidentified internal members as new Users
    @users.concat create_and_return_internal_users(new_internal_users)
  end

  # TODO: Rename this to "People" .html and path
  def account
    @SOCIAL_BIO_TEXT_LENGTH_MAX = 192
    @EMAIL_SUBJECT_TEXT_LENGTH_MAX = 65
    @NUM_LATEST_TRACKED_EMAIL_ACTIVITY_LIMIT = 8 # Number of newest tracked email activities shown in timeline

    @accounts = Account.eager_load(:projects, :user).where(organization_id: current_user.organization_id).order("upper(accounts.name)") # for account picklist

    external_emails = @params[:external].present? ? @params[:external].map{|p| p.second} : []
    internal_emails = @params[:internal].present? ? @params[:internal].map{|p| p.second} : []
    account_contacts_emails = (@account.present? && @account.contacts.present?) ? @account.contacts.map{|c| c.email.downcase}.sort : []

    people_emails = external_emails | internal_emails - [current_user.email.downcase]
    account_contacts_emails = (account_contacts_emails - people_emails)[0...NUM_ACCOUNT_CONTACT_SHOW_LIMIT]  # filter by/remove users already in e-mail thread, then truncate list

    @people_with_profile = people_emails.each_with_object([]) { |e, memo| memo << { email: e, user: current_user.organization.users.find_by_email(e), contact: current_user.organization.contacts.find_by_email(e), profile: Profile.find_or_create_by_email(e), name_from_params: ((@params[:external].find{|p| p.second == e} if @params[:external].present?) || (@params[:internal].find{|p| p.second == e} if @params[:internal].present?) || [nil]).first } }
    @account_contacts_with_profile = account_contacts_emails.each_with_object([]) { |e, memo| memo << {email: e, profile: Profile.find_or_create_by_email(e), contact: current_user.organization.contacts.find_by_email(e) } }

    people_emails += @account_contacts_with_profile.map{|p| p[:email]}

    # people_emails = ['joe@plugandplaytechcenter.com']
    # people_emails = ['nat.ferrante@451research.com','pauloshan@yahoo.com','sheila.gladhill@browz.com', 'romeo.henry@mondo.com', 'lzion@liveintent.com']
    tracking_requests_this_pastmonth = current_user.tracking_requests.find_by_any_recipient(people_emails).where(sent_at: 1.month.ago.midnight..Time.current).order("sent_at DESC") #TODO: This line and the subsequent code is related to issue #1258.
    
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

  # def salesforce
  #   @salesforce_account = @account.salesforce_accounts.first if @account.present?
  #   @salesforce_opportunity = @project.salesforce_opportunity if @project.present?
  #   render layout: 'empty'
  # end

  def custom_view
    if current_user.pro? && @salesforce_user.present? && current_user.oauth_provider == User::AUTH_TYPE[:Gmail]
      params[:close_date] = Project::CLOSE_DATE_RANGE[:ThisQuarter] if params[:close_date].blank?  # Default view is: Close date = 'This Qtr'

      visible_projects = Project.visible_to(current_user.organization_id, current_user.id)
      visible_projects = visible_projects.close_date_within(params[:close_date]) unless params[:close_date] == 'Any'
      visible_projects = visible_projects.where.not(stage: current_user.organization.get_closed_stages) if params[:close_date] == Project::CLOSE_DATE_RANGE[:ThisQuarterOpen]

      @current_user_projects = visible_projects.owner_of(current_user.id).select("projects.*, false AS daily, false AS weekly")
      subscribed_projects = visible_projects.select("project_subscribers.daily, project_subscribers.weekly").joins(:subscribers).where(project_subscribers: {user_id: current_user.id}).group("project_subscribers.daily, project_subscribers.weekly")

      # Load data for the charts if current user owns any projects with current filters
      unless @current_user_projects.blank?
        project_engagement_30d = Project.count_activities_by_category(@current_user_projects.ids, current_user.organization.domain, [current_user.email], 30.days.ago.midnight.utc).group_by { |p| p.id }
        if project_engagement_30d.blank?
          @data_left = [] and @categories = []
        else
          @data_left = project_engagement_30d.map do |pid, activities|
            proj = @current_user_projects.find { |p| p.id == pid }
            Hashie::Mash.new({ id: proj.id, name: proj.name, deal_size: proj.amount, close_date: proj.close_date, y: activities, total: activities.inject(0){|sum,a| sum += (a.num_activities.present? ? a.num_activities : 0)} }) if proj.present?  # else nil
          end
        end
        @data_left.compact!
        @data_left.sort!{ |d1, d2| (d1.total == d2.total) ? d1.name.upcase <=> d2.name.upcase : d2.total <=> d1.total } # sort using tiebreaker: opportunity name, case-insensitive in alphabetical order

        # compute Interaction Time per Account for this user on the fly
        email_time = current_user.email_time_by_project(@current_user_projects.ids, 30.days.ago.midnight.utc)
        meeting_time = current_user.meeting_time_by_project(@current_user_projects.ids, 30.days.ago.midnight.utc)
        attachment_time = current_user.sent_attachments_by_project(@current_user_projects.ids, 30.days.ago.midnight.utc)
        @interaction_time_per_account = email_time.map do |p|
          Hashie::Mash.new(name: p.name, id: p.id, deal_size: p.amount, close_date: p.close_date, 'Meetings': 0, 'Attachments': 0, 'Sent E-mails': p.outbound, 'Read E-mails': p.inbound, total: p.inbound + p.outbound)
        end
        meeting_time.each do |p|
          i_t = @interaction_time_per_account.find { |it| it.id == p.id }
          if i_t.nil?
            @interaction_time_per_account << Hashie::Mash.new(name: p.name, id: p.id, deal_size: p.amount, close_date: p.close_date, 'Meetings': p.total_meeting_hours, 'Attachments': 0, 'Sent E-mails': 0, 'Read E-mails': 0, total: p.total_meeting_hours)
          else
            i_t.Meetings = p.total_meeting_hours
            i_t.total += p.total_meeting_hours
          end
        end
        attachment_time.each do |p|
          attachment_t = p.attachment_count * User::ATTACHMENT_TIME_SEC
          i_t = @interaction_time_per_account.find { |it| it.id == p.id }
          if i_t.nil?
            @interaction_time_per_account << Hashie::Mash.new(name: p.name, id: p.id, deal_size: p.amount, close_date: p.close_date, 'Meetings': 0, 'Attachments': attachment_t, 'Sent E-mails': 0, 'Read E-mails': 0, total: attachment_t)
          else
            i_t.Attachments = attachment_t
            i_t.total += attachment_t
          end
        end
        @interaction_time_per_account.sort_by! { |it| it.total.to_f }.reverse!
        # take the top 5 interaction time per account, currently allotted space only fits about 5 categories on xAxis before labels are cut off
        @interaction_time_per_account = @interaction_time_per_account.take(5)

        @categories = @data_left.inject([]) do |memo, d|
          d.y.each {|a| memo = memo | [a.category]}
          memo
        end  # get only categories that have data

        # get data for Stages chart
        set_top_dashboard_data(project_ids: @current_user_projects.ids, user_ids: [current_user.id])
        # @no_progress = true

        # get data for Forecast chart
        forecast_result = @current_user_projects.order(:close_date).pluck(:forecast, :close_date, :amount, :stage)
        @forecast_data = {
            closed_won: { values: [], total: 0 },
            commit: { values: [], total: 0 },
            best_case: { values: [], total: 0 },
        }
        forecast_result.each do |fr|
          case fr[0] # forecast
            when 'Closed'
              if current_user.organization.get_winning_stages.include? fr[3] # stage
                @forecast_data[:closed_won][:total] += (fr[2] || 0) # amount
                @forecast_data[:commit][:total] += (fr[2] || 0) # amount
                @forecast_data[:best_case][:total] += (fr[2] || 0) # amount
                @forecast_data[:closed_won][:values] += [ [fr[1].to_datetime.to_i * 1000, @forecast_data[:closed_won][:total].to_i] ]
              end
            when 'Commit'
              @forecast_data[:commit][:total] += (fr[2] || 0) # amount
              @forecast_data[:best_case][:total] += (fr[2] || 0) # amount
              @forecast_data[:commit][:values] += [ [fr[1].to_datetime.to_i * 1000, @forecast_data[:commit][:total].to_i] ]
              @forecast_data[:best_case][:values] += [ [fr[1].to_datetime.to_i * 1000, @forecast_data[:best_case][:total].to_i] ]
            when 'Best Case'
              @forecast_data[:best_case][:total] += (fr[2] || 0) # amount
              @forecast_data[:best_case][:values] += [ [fr[1].to_datetime.to_i * 1000, @forecast_data[:best_case][:total].to_i] ]
          end
        end

        # Add 'ends' for the data (e.g. begin at start of quarter, stop at end of quarter, connect data at current date)
        date_range = Project.get_close_date_range(params[:close_date])
        date_range_start = date_range.first.to_i * 1000
        current_date_epoch = Date.current.to_datetime.to_i * 1000
        date_range_end = date_range.last.to_i * 1000
        if @forecast_data[:closed_won][:values].empty?
          @forecast_data[:closed_won][:values] = [ [date_range_start, 0], [current_date_epoch, 0] ]
        else
          start = @forecast_data[:closed_won][:values].first.first
          if date_range_start < start
            @forecast_data[:closed_won][:values] = [ [date_range_start, 0] ] + @forecast_data[:closed_won][:values]
          end
          ends = @forecast_data[:closed_won][:values].last.first
          if current_date_epoch > ends
            @forecast_data[:closed_won][:values] += [ [current_date_epoch, @forecast_data[:closed_won][:total].to_i] ]
          end
        end

        [@forecast_data[:commit], @forecast_data[:best_case]].each do |fd|
          if fd[:values].empty?
            fd[:values] = [ [current_date_epoch, @forecast_data[:closed_won][:total].to_i], [date_range_end, fd[:total].to_i] ]
          else
            start = fd[:values].first.first
            if current_date_epoch < start
              fd[:values] = [ [current_date_epoch, @forecast_data[:closed_won][:total].to_i] ] + fd[:values]
            end
            ends = fd[:values].last.first
            if date_range_end > ends
              fd[:values] += [ [date_range_end, fd[:total].to_i] ]
            end
          end
        end
      end

      # Load project data for "My Opportunities"
      @projects = (subscribed_projects + @current_user_projects).uniq(&:id).sort_by{|p| p.name.upcase} # projects/opportunities user owns or to which user is subscribed
      unless @projects.empty?
        project_ids_a = @projects.map(&:id)

        @sparkline = Project.count_activities_by_day_sparkline(project_ids_a, current_user.time_zone)
        # @risk_scores = Project.new_risk_score(project_ids_a, current_user.time_zone)
        @open_risk_count = Project.open_risk_count(project_ids_a)
        # @days_to_close = Project.days_to_close(project_ids_a)
        @project_days_inactive = visible_projects.joins(:activities).where.not(activities: { category: [Activity::CATEGORY[:Note], Activity::CATEGORY[:Alert], Activity::CATEGORY[:NextSteps]] }).where('activities.last_sent_date <= ?', Time.current).maximum("activities.last_sent_date") # get last_sent_date
        @project_days_inactive.each { |pid, last_sent_date| @project_days_inactive[pid] = Time.current.to_date.mjd - last_sent_date.in_time_zone.to_date.mjd } # convert last_sent_date to days inactive
        @next_meetings = Activity.meetings.next_week.select("project_id, min(last_sent_date) as next_meeting").where(project_id: project_ids_a).group("project_id")
        @next_meetings = Hash[@next_meetings.map { |p| [p.project_id, p.next_meeting] }]
      end
    end

    render layout: 'empty'
  end

  def company
    if current_user.plus?
      @SOCIAL_BIO_TEXT_LENGTH_MAX = 192
      # puts '***********', @account.present?
      # puts @account.domain.present? if @account.present?
      # puts @account.domain if @account.present?
      # puts @project.present?
      # puts @project.name if @project.present?
      # p @params
      # use account domain as company domain
      domain = if @account.present? && @account.domain.present?
                 @account.domain
               # get the most frequent external domain out of email people to use as company domain
               elsif @params[:external].present?
                 external_emails = @params[:external].map { |person| URI.unescape(person.second, '%2E') }
                 freq_domain_email = external_emails.group_by { |email| get_domain(email) }.values.max_by(&:size).first
                 get_domain(freq_domain_email)
               # if no external people, use internal domain
               elsif @params[:internal].present?
                 get_domain(current_user.email) # don't use organization.domain, could be a gmail user
               end
      @company = CompanyProfile.find_or_create_by_domain(domain) if domain && valid_domain?(domain)
      # @company = CompanyProfile.find_or_create_by_domain(@account.domain) if @account.present? && @account.domain.present?
    end
  end

  def attachments
    return unless @service
    @emails = @params[:external].map { |person| URI.unescape(person.second, '%2E') } if @params[:external].present?
    @emails = @params[:internal].map { |person| URI.unescape(person.second, '%2E') }.reject { |email| email == current_user.email } if @emails.blank? && @params[:internal].present?
    return if @emails.blank?
    email_filter_string = @emails.map { |email| "from:#{email} OR to:#{email}" }.join(' OR ')
    message_list = @service.list_user_messages('me', q: email_filter_string + ' has:attachment -in:chats', max_results: 100)
    return if message_list.messages.blank?
    @messages = []
    # make batched GET requests for attachment emails
    message_list.messages.each_slice(50) do |msg_list_slice|
      @service.batch do |service|
        msg_list_slice.each do |msg|
          service.get_user_message('me', msg.id) do |m, error|
            next if error || m.blank? || m.payload.mime_type != 'multipart/mixed'
            parts = m.payload.parts
            headers = m.payload.headers
            begin
              from = parse_email(headers.find { |h| h.name == 'From' }.value)
              # boolean for deciding whether attachment was sent or received
              internal = from.address == current_user.email || from.name == get_full_name(current_user)
              to = headers.select { |h| h.name == 'To' || h.name == 'Cc' || h.name == 'Bcc' }.compact.map(&:value).map { |val| Mail::AddressList.new(val) }.map(&:addresses).flatten
              to.reject { |email| email.address == current_user.email || email.name == get_full_name(current_user) } if internal
              message_id = headers.find { |h| h.name == 'Message-ID' }.value
              atts = parts[1..parts.length]
              attachments = atts.reject { |att| att.filename.blank? || att.headers.find { |h| h.name == 'Content-Disposition' }.value.start_with?('inline') }
                                .map { |att| { filename: att.filename, part_id: att.part_id, mime_type: att.mime_type, attachment_id: att.body.attachment_id, file_size: att.body.size } }
              next if attachments.blank?
              @messages << Hashie::Mash.new({ from: from, to: to, message_id: message_id, internal: internal, internal_date: m.internal_date, id: m.id, attachments: attachments })
            rescue NoMethodError
              puts '~~~~~~~~~~ Some headers missing from this email with attachment ~~~~~~~~~~~'
              from = headers.find { |h| h.name == 'From' }
              puts 'From: ' + (from ? from.value : '(n/a)')
              to = headers.find { |h| h.name == 'To' }
              puts 'To: ' + (to ? to.value : '(n/a)')
              cc = headers.find { |h| h.name == 'Cc' }
              puts 'CC: ' + (cc ? cc.value : '(n/a)')
              bcc = headers.find { |h| h.name == 'Bcc' }
              puts 'BCC: ' + (bcc ? bcc.value : '(n/a)')
              message_id = headers.find { |h| h.name == 'Message-ID' }
              puts 'Message-ID: ' + (message_id ? message_id.value : '(n/a)')
              content_disposition = headers.find { |h| h.name == 'Content-Disposition' }
              puts 'Content-Disposition: ' + (content_disposition ? content_disposition.value : '(n/a)')
            end
          end
        end
      end
    end
  end

  def download
    @service.get_user_message_attachment('me', params['id'], params['attachment_id']) { |attachment| send_data attachment.data, filename: params['filename'], type: params['mime_type'] }
  end

  # def contacts
  #   @project_members = @project.project_members
  #   @suggested_members = @project.project_members_all.pending
  # end


  # Note: params[:external] and params[:internal] is forwarded to extension_account_path unfiltered
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

  # Tracking Dashboard tab opened by the Tracking button  
  def dashboard
    if current_user.plus?
      # Daily trend (last month, sent and opens)
      tracking_requests_pastmo_h = current_user.tracking_requests.from_lastmonth.group_by{|tr| tr.sent_at.to_date}.map{|d,tr| [d, tr.length]}.to_h
      @emails_sent_lastmonth = (Date.today-1.month..Date.today).map{|d| [d, (tracking_requests_pastmo_h[d] ? tracking_requests_pastmo_h[d] : 0)]}

      tracking_events_pastmo_h = current_user.tracking_requests.map do |tr|
        tr.tracking_events.from_lastmonth.map{ |te| te.created_at.to_date }
      end.flatten.group_by{|d| d}.map{|d,c| [d, c.length]}.to_h
      @emails_opened_lastmonth = (Date.today-1.month..Date.today).map{|d| [d, (tracking_events_pastmo_h[d] ? tracking_events_pastmo_h[d] : 0)]}

      @event_dates = (Date.today-1.month..Date.today).map{|d| d.strftime("%b %e")}

      # Day of the Week and Hourly trend (last month, sent and opens)
      tracking_requests_daily_hourly_pastmo_h = current_user.tracking_requests.from_lastmonth.map{ |tr| tr.sent_at.in_time_zone(current_user.time_zone) }.group_by{|d,tr| [d.strftime("%H").to_i, d.wday]}.map{|k,d| [k, d.length]}.to_h
      @emails_daily_hourly_sent_lastmonth = []
      (0..23).map do |h|
        (0..6).map do |d|
          @emails_daily_hourly_sent_lastmonth << [h, d, (tracking_requests_daily_hourly_pastmo_h[[h,d]] ? tracking_requests_daily_hourly_pastmo_h[[h,d]] : nil)]
        end
      end

      tracking_events_daily_hourly_pastmo_h = current_user.tracking_requests.map do |tr|
        tr.tracking_events.from_lastmonth.map{ |te| te.created_at.in_time_zone(current_user.time_zone) }
      end.flatten.compact.group_by{|d| [d.strftime("%H").to_i, d.wday]}.map{|k,d| [k, d.length]}.to_h
      @emails_daily_hourly_opened_lastmonth = []
      (0..23).map do |h|
        (0..6).map do |d|
          @emails_daily_hourly_opened_lastmonth << [h, d, (tracking_events_daily_hourly_pastmo_h[[h,d]] ? tracking_events_daily_hourly_pastmo_h[[h,d]] : nil)]
        end
      end
    else
      @event_dates = ["Jan 7", "Jan 8", "Jan 9", "Jan 10", "Jan 11", "Jan 12", "Jan 13", "Jan 14", "Jan 15", "Jan 16", "Jan 17", "Jan 18", "Jan 19", "Jan 20", "Jan 21", "Jan 22", "Jan 23", "Jan 24", "Jan 25", "Jan 26", "Jan 27", "Jan 28", "Jan 29", "Jan 30", "Jan 31", "Feb 1", "Feb 2", "Feb 3", "Feb 4", "Feb 5", "Feb 6", "Feb 7"]
    end

    render layout: 'empty'
  end

  def dashboard_drilldown
    start_date = Time.at(params[:startDate].to_i).utc if params[:startDate].present?
    end_date = Time.at(params[:endDate].to_i).utc if params[:endDate].present?
    if params[:type] == 'Sent'
      reqs_result = current_user.tracking_requests.from_lastmonth

      reqs_result = reqs_result.where(sent_at: start_date..end_date) if (start_date && end_date)
      reqs_result = reqs_result.where("EXTRACT(DOW FROM sent_at AT TIME ZONE 'UTC' AT TIME ZONE '#{current_user.time_zone}') = " + params[:dayOfWeek]) if params[:dayOfWeek].present?
      reqs_result = reqs_result.where("EXTRACT(HOUR FROM sent_at AT TIME ZONE 'UTC' AT TIME ZONE '#{current_user.time_zone}') = " + params[:hourOfDay]) if params[:hourOfDay].present?

      result = reqs_result.order("sent_at DESC").map do |tr|
        { recipients: tr.recipients, sent_at: tr.sent_at, subject: tr.subject, email_id: tr.email_id }
      end
    else # params[:type] == 'Opened'
      # evnts_result = current_user.tracking_requests.map do |tr|
      #   tr.tracking_events.select { |te| te.created_at.to_date }
      #   # tr.tracking_events.from_lastmonth.map{ |te| te.created_at.to_date }
      # end
      evnts_result = current_user.tracking_requests.select("tracking_requests.*, tracking_events.*, tracking_requests.id AS tracking_request_id, tracking_events.created_at AS opened_at").joins(:tracking_events).where(tracking_events: {created_at: 1.month.ago.midnight..Time.current})

      evnts_result = evnts_result.where(tracking_events: {created_at: start_date..end_date}) if (start_date && end_date)
      evnts_result = evnts_result.where("EXTRACT(DOW FROM tracking_events.created_at AT TIME ZONE 'UTC' AT TIME ZONE '#{current_user.time_zone}') = " + params[:dayOfWeek]) if params[:dayOfWeek].present?
      evnts_result = evnts_result.where("EXTRACT(HOUR FROM tracking_events.created_at AT TIME ZONE 'UTC' AT TIME ZONE '#{current_user.time_zone}') = " + params[:hourOfDay]) if params[:hourOfDay].present?

      # Grouped by e-mail sent
      evnts_result_h = {}
      evnts_result.order("opened_at DESC").each do |r|
        evnts_result_h[r.tracking_request_id] = Hashie::Mash.new({ id: r.tracking_request_id, recipients: r.recipients, sent_at: r.sent_at, subject: r.subject, email_id: r.email_id, last_opened_at: r.opened_at, tracking_requests: []}) if evnts_result_h[r.tracking_request_id].blank?
        evnts_result_h[r.tracking_request_id].tracking_requests += [{ opened_at: r.opened_at, user_agent: r.user_agent, place_name: r.place_name, event_type: r.event_type, domain: r.domain }]
      end
      result = evnts_result_h.sort_by {|k, r| r.last_opened_at}.reverse.map do |k, r|
        { last_opened_at: r.last_opened_at, recipients: r.recipients.to_a, sent_at: r.sent_at, subject: r.subject, email_id: r.email_id, tracking_requests: r.tracking_requests.to_a }
      end
    end

    # puts "\n\nResult="
    # puts result
    render json: { type: params[:type], result: result }
  end

  private

  # Filter params[:external] and params[:internal] passed from the Chrome extension by converting to lowercase, validating email addresses, and removing duplicates; params[:bcc_email] and params[:email] are validated and converted to lowercase.
  # Returns a filtered list in @params.
  def filter_params
    @params = {}
    external = []
    if params[:external].present?
      params[:external].values.each do |n, e|
        external << [n, e.downcase] if (e.present? && valid_email?(e))
      end 
      @params[:external] = external.uniq[0...NUM_PARAM_LIST_LIMIT]
    end
    internal = []
    if params[:internal].present?
      params[:internal].values.each do |n, e|
        internal << [n, e.downcase] if (e.present? && valid_email?(e))
      end 
      @params[:internal] = internal.uniq[0...NUM_PARAM_LIST_LIMIT]
    end
    @params[:bcc_email] = params[:bcc_email].downcase if params[:bcc_email].present? && valid_email?(params[:bcc_email])
    @params[:email] = params[:email].downcase if params[:email].present? && valid_email?(params[:email])
  end 

  def set_salesforce_user
    return if @salesforce_user.present? || current_user.nil?

    @salesforce_base_URL = OauthUser.get_salesforce_instance_url(current_user.organization_id)

    @salesforce_user = SalesforceController.get_sfdc_oauthuser(user: current_user) if current_user.pro?
  end

  # Old before_action helper -- FOR REFERENCE ONLY!
  def set_account_and_project_old
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
          
          sfdc_client = SalesforceService.connect_salesforce(user: current_user)

          sfdc_account_id = find_matching_sfdc_account(sfdc_client, ex_emails)
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

              SalesforceController.import_sfdc_contacts_and_add_as_members(client: sfdc_client, account: @account, sfdc_account: sfa) if sfa.save
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
    @members = @all_members.first(NUM_ACCOUNT_CONTACT_SHOW_LIMIT)
  end

  # (New) before_action helper: For users belonging to at least the "Plus" plan, this determines a matching account+opportunity from the set of recipients (the external contacts from the active e-mail) to facilitate Contacts management. i.e., if no external contacts exist, no account or opportunity is returned.
  # Note: E-mail domains that are typically "invalid" such as "gmail.com", "yahoo.com", "hotmail.com" may be used to identify a "matching" account if we can find the Contact with the e-mail.  Otherwise, we stop and do not attempt to identify a matching account using "invalid" domains, because these domains are too general and can easily match the wrong account.
  def set_account_and_project
    return if @params[:external].blank? || !current_user.plus?

    external = @params[:external].map { |person| person.map { |info| URI.unescape(info, '%2E') } }
    ex_emails = external.map(&:second)

    contacts = Contact.joins(:account).where(email: ex_emails, accounts: { organization_id: current_user.organization_id })

  
    if contacts.present?
      # Match by account contacts
      @account ||= contacts.first.account
    else
      # ex_emails = ["nat.ferrante@451research.com","pauloshan@yahoo.com","sheila.gladhill@browz.com", "romeo.henry@mondo.com", "lzion@liveintent.com","invalid'o@gmail.com"]
      # group by ex_emails by domain frequency, order by most frequent domain
      ex_emails = ex_emails.group_by { |email| get_domain(email) }.values.sort_by(&:size).flatten 
      order_emails_by_domain_freq = ex_emails.map { |email| "email = #{Contact.sanitize(email)} DESC" }.join(',')
      # find all contacts within current_user org that match the external emails, in the order of ex_emails
      contacts = Contact.joins(:account).where(email: ex_emails, accounts: { organization_id: current_user.organization_id }).order(order_emails_by_domain_freq) 


      # Match by account domains
      ex_emails = ex_emails.reject { |email| get_domain(email).downcase == current_user.organization.domain.downcase || !valid_domain?(get_domain(email)) } # remove e-mails with domains that are too general

      return if ex_emails.blank?  # quit if no "valid" e-mails remain

      # Sanitize domains before injecting
      domains = ex_emails.map { |email| Contact.sanitize(get_domain(email))[1...-1] } # remove leading and trailing apostrophe

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
  #     SalesforceAccount.load_accounts(current_user) 
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

  # Helper method for creating people, used in set_account_and_project_old & create_project (@project should already be set before calling this)
  # By default, all internal people are added to @project as confirmed members, all external people are added to @project as suggested members
  def create_people(status=ProjectMember::STATUS[:Pending])
    if @params[:internal].present?
      internal = @params[:internal].map { |person| person.map { |info| URI.unescape(info, '%2E') } } 
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

    external = @params[:external].present? ? @params[:external].map { |person| person.map { |info| URI.unescape(info, '%2E') } } : []
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
      next if User.find_by_email(u[:email]).present? || u[:email].nil?

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

  def parse_email(email)
    begin
      Mail::Address.new(email)
    rescue StandardError => e
      # email probably has non-ascii characters, try to extract just the e-mail address
      email.match(/.*<(.*)>/) do |match|
        Hashie::Mash(address: match[1])
      end
    end
  end

  def get_tracking_setting
    ts = TrackingSetting.where(user: current_user).first_or_create do |ts|
      ts.last_seen = DateTime.now
    end
    ts
  end

  def get_google_service
    return unless current_user.plus? && current_user.oauth_provider == User::AUTH_TYPE[:Gmail]
    # connect to Gmail
    secrets = Google::APIClient::ClientSecrets.new(
      {
        "web" => {
          "access_token" => current_user.fresh_token,
          "refresh_token" => current_user.oauth_refresh_token,
          "client_id" => ENV['google_client_id'],
          "client_secret" => ENV['google_client_secret']
        }
      }
    )
    @service = Gmail::GmailService.new
    @service.authorization = secrets.to_authorization
  end
end
