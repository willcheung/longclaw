require 'geocoder'
require 'mail'
require 'resolv'

# controller class for tracking e-mails
class TrackingController < ApplicationController
  layout "tracking"

  def index
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

    @trackings = TrackingRequest.includes(:tracking_events)
                     .where(user_id: current_user.id)
                     .page(page)
                     .order('tracking_events.date DESC, sent_at DESC')
    json = {requests: @trackings.as_json(include: { tracking_events: { methods: :client }}),
            settings: get_tracking_setting }
    render json: json
  end

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
    tr = check_tracking_id(tracking_id)
    event_date = DateTime.current
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
          date: event_date
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
    event_count = {count: TrackingEvent.joins(:tracking_request).where(date: ts.last_seen..Time.now, tracking_requests: { user_id: current_user.id}).count}
    render json: event_count
  end

  def new_event_objects
    ts = get_tracking_setting
    tes = TrackingEvent.joins(:tracking_request).where(date: ts.last_seen..Time.now, tracking_requests: { user_id: current_user.id})
    render json: tes.to_json({ methods: :client })
  end

  def seen
    ts = TrackingSetting.where(user: current_user).first_or_create

    ts.last_seen = DateTime.now
    ts.save
    result = {status: 'ok'}
    render json: result
  end

  private

  def get_tracking_setting
    ts = TrackingSetting.where(user: current_user).first_or_create do |ts|
      ts.last_seen = DateTime.now
    end
    ts.save
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

  def check_tracking_id(tracking_id)
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
