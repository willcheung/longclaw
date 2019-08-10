require 'geocoder'
require 'mail'
require 'resolv'

# controller class for tracking e-mails
class TrackingController < ApplicationController
  layout false

  def index
    # DEPRECATED!
    @device_to_icon = {
        'desktop' => 'fa-desktop',
        'smartphone' => 'fa-mobile',
        'tablet' => 'fa-tablet',
        'console' => 'fa-gamepad',
        'portable media player' => 'fa-play',
        'tv' => 'fa-tv',
        'car browser' => 'fa-car',
        'camera' => 'fa-camera'
    }
    # TODO: use a time window for this
    @trackings = TrackingRequest.includes(:tracking_events).where(user_id: current_user.id).order('tracking_events.date DESC')
    @opened, @unopened = @trackings.partition {|t| t.tracking_events.size > 0}
    @tracking_setting = get_tracking_setting
  end

  def list
    page = params[:page].present? ? params[:page] : 1

    # last 30 days of emails sent + their history and emails opened + their history
    sql_where = "tracking_requests.tracking_id in (
                 select tracking_id from tracking_requests where user_id='#{current_user.id}' and sent_at > NOW() - interval '60' day
                  UNION
                 select e.tracking_id from tracking_events e join tracking_requests r on e.tracking_id=r.tracking_id where date > NOW() - interval '60' day and r.user_id='#{current_user.id}')"

    @trackings = TrackingRequest.includes(:tracking_events)
                     .where(sql_where)
                     .page(page)
                     .order('tracking_events.date DESC NULLS LAST').order('sent_at DESC');
    json = {requests: @trackings.as_json(include: { tracking_events: { methods: :client }}),
            settings: get_tracking_setting }
    render json: json
  end

  # create tracking request upon sending email
  def create
    data = Hashie::Mash.new(JSON.parse(request.body.read))
    if current_user.email == data.user_email
      tr = TrackingRequest.create(
          message_id: data.message_id,
          email_id: data.email_id, # internal email_id like the google mail id
          tracking_id: data.tracking_id,
          recipients: to_email_address(data.recipients),
          subject: data.subject,
          sent_at: data.sent_at.to_datetime,
          user_id: current_user.id,
          status: 'active'
      )
      render :json => tr
    else
      render json: {}, status: 401
    end
  end

  # callback from tracking img tags
  def view
    tracking_id = params[:tracking_id]
    tr = find_tracking_id(tracking_id)
    event_date = DateTime.current

    if tr
      # Whenever there's a new img view, delete cache so event_count will increase
      Rails.cache.delete("event_count_"+"#{tr.user_id}")
      Rails.cache.delete("tracking_setting_"+"#{tr.user_id}")
      Rails.cache.delete("event_object_tes_"+"#{tr.user_id}")
      Rails.cache.delete("event_object_trs_"+"#{tr.user_id}")
      Rails.cache.delete("tr_past_month_"+"#{tr.user_id}")
    end

    if tr && not_viewed_by_self(tr) && !within_threshold(tracking_id, event_date)
      user_agent = request.headers['user-agent']
      start = Time.now
      host_name = Resolv.getname(request.remote_ip) rescue 'Unknown' # timeout 5s
      puts "Resolving #{request.remote_ip} took #{Time.now - start} ms"
      domain = extract_domain_name(host_name)
      # if request comes from a google proxy, we can't locate the user
      location = if host_name.start_with?('google-proxy')
                   user_agent = ''
                   'Gmail'
                 else
                   location_lookup(request.remote_ip)
                 end
      TrackingEvent.create(
          tracking_id: tr.tracking_id,
          user_agent: user_agent,
          place_name: location,
          domain: domain,
          event_type: 'email-view',
          date: DateTime.current # changing this to a newer timestamp as this might be 30 seconds later than event_date and in the meantime users could have changed their 'last seen' timestamp
      )
    end
    expires_now
    send_data(Base64.decode64("R0lGODlhAQABAPAAAAAAAAAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw=="), :type => "image/gif", :disposition => "inline")

  end

  def toggle
    tracking_id = params[:tracking_id]
    tr = TrackingRequest.find_by_tracking_id(tracking_id)
    if tr
      tr.toggle_status
      tr.save
      result = {status: tr.status}
    else
      result = {error: "No tracking request found"}
    end
    render json: result
  end

  def new_events
    ts = get_tracking_setting

    #event_count = Rails.cache.fetch("event_count_"+"#{current_user.id}", expires_in: 30.minutes) do
      event_count = {count: TrackingEvent.joins(:tracking_request).where(date: ts.last_seen..Time.now, tracking_requests: { user_id: current_user.id}).count}
    #end

    render json: event_count
  end

  def new_event_objects
    ts = get_tracking_setting

    #tes = Rails.cache.fetch("event_object_tes_"+"#{current_user.id}", expires_in: 30.minutes) do
      tes = TrackingEvent.joins(:tracking_request).where(date: ts.last_seen..Time.now, tracking_requests: { user_id: current_user.id})
    #end

    #new_trs = Rails.cache.fetch("event_object_trs_"+"#{current_user.id}", expires_in: 30.minutes) do
      new_trs = TrackingRequest.where(sent_at: ts.last_seen..Time.now, user_id: current_user.id).order("sent_at ASC")
    #end

    render json: { new_events: tes.as_json({ methods: :client }),
                   new_requests: new_trs.as_json,
                   settings: get_tracking_setting
    }
  end

  def seen
    ts = TrackingSetting.where(user: current_user).first_or_create
    ts.update(last_seen: DateTime.now)

    # Whenever there's a new tracking window view, delete cache so event_count will reset
    Rails.cache.delete("event_count_"+"#{current_user.id}")
    Rails.cache.delete("tracking_setting_"+"#{current_user.id}")
    Rails.cache.delete("event_object_tes_"+"#{current_user.id}")
    Rails.cache.delete("event_object_trs_"+"#{current_user.id}")

    result = {status: 'ok'}
    render json: result
  end

  private

  def get_tracking_setting
    ts = Rails.cache.fetch("tracking_setting_"+"#{current_user.id}", expires_in: 30.minutes) do
      ts = TrackingSetting.where(user: current_user).first_or_create
      ts.update(last_seen: DateTime.now) if ts.last_seen == nil or ts.last_seen == ""
      ts
    end
    ts
  end

  def location_lookup(ip)
    start = Time.now
    address = Geocoder.address(ip) rescue 'Unknown'
    puts "Geocoding #{ip} took #{Time.now - start} ms"
    address
  end

  def to_email_address(emails)
    emails.map { |a| parse_email(a) }.reject(&:nil?)
  end

  def parse_email(a)
    begin
      Mail::Address.new(a).address
    rescue StandardError => e
      # a probably has non-ascii characters, try to extract just the e-mail address
      a.match(/.*<(.*)>/) do |match|
        match[1]
      end
    end
  end

  def not_viewed_by_self(tracking_request)
    current_user.nil? || current_user.id != tracking_request.user_id
  end

  def find_tracking_id(tracking_id)
    TrackingRequest.find_by_tracking_id_and_status(tracking_id, 'active')
  end

  # extract the domain part from the host name, or nil if host name doesn't match
  def extract_domain_name(host)
    md = /(^|\.)([a-zA-Z0-9-]{1,63}\.[a-zA-Z0-9-]{1,63})$/.match(host)
    md ? md[2] : nil
  end

  # ignore TE happening withing `threshold` seconds
  # new config var. If set to -1 will be ignored
  def within_threshold(tracking_id, date)
    threshold = ENV['tracking_threshold_seconds'].to_i
    threshold = 15 if threshold.zero?

    if threshold == -1
      false
    else
      te = TrackingEvent.where(date: threshold.seconds.ago(date)..date, tracking_id: tracking_id).first
    end
  end

end
