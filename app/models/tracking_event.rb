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
#

require 'device_detector'

class TrackingEvent < ActiveRecord::Base
  belongs_to :tracking_request, class_name: "TrackingRequest", foreign_key: 'tracking_id'

  def device
    DeviceDetector.new(self.user_agent)
  end
end
