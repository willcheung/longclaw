# == Schema Information
#
# Table name: tracking_events
#
#  id          :integer          not null, primary key
#  tracking_id :string
#  date        :datetime
#  user_agent  :string
#  place_name  :string
#  event_type  :string
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  domain      :string
#
# Indexes
#
#  index_tracking_events_on_date         (date)
#  index_tracking_events_on_tracking_id  (tracking_id)
#

require 'device_detector'

class TrackingEvent < ActiveRecord::Base
  belongs_to :tracking_request, :primary_key => 'tracking_id', class_name: "TrackingRequest", foreign_key: 'tracking_id'
  has_one :user, through: "tracking_request", class_name: "User"

  def device
    DeviceDetector.new(self.user_agent)
  end

  def client
    dd = DeviceDetector.new(self.user_agent)
    { device_name: dd.device_name , device_type: dd.device_type, name: dd.name, os_name: dd.os_name }
  end
end
