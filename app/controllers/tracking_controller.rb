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
    @trackings = TrackingRequest.includes(:tracking_events).where(user_id: current_user.id).order('tracking_events.date DESC')
    @opened, @unopened = @trackings.partition {|t| t.tracking_events.size > 0}
    @tracking_setting = get_tracking_setting
    #@trackings = TrackingRequest.includes(:tracking_events).where(:belong)

  end

  def create
    data = Hashie::Mash.new(JSON.parse(request.body.read))
    # TODO validation
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
  end

  # callback from tracking img tags
  def view
    tracking_id = params[:tracking_id]
    tr = check_tracking_id(tracking_id)
    if tr && not_viewed_by_self(tr)
      user_agent = request.headers['user-agent']
      host_name = Resolv.getname(request.remote_ip)
      # if request comes from a google proxy, we can't locate the user
      location = if host_name.start_with?('google-proxy') then
                   user_agent = ''
                   'Gmail'
                 else
                   location_lookup(request.remote_ip)
                 end
      TrackingEvent.create(
          tracking_id: tr.tracking_id,
          user_agent: user_agent,
          place_name: location,
          event_type: 'email-view',
          date: DateTime.current
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
    Geocoder.address(ip)
  end

  def to_email_address(emails)
    emails.map {|a| Mail::Address.new(a).address}
  end

  def not_viewed_by_self(tracking_request)
    current_user.nil? || current_user.id != tracking_request.user_id
  end

  def check_tracking_id(tracking_id)
    TrackingRequest.find_by_tracking_id_and_status(tracking_id, 'active')
  end
end
