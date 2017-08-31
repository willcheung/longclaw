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

require 'device_detector'

class TrackingEvent < ActiveRecord::Base
  belongs_to :tracking_request, :primary_key => 'tracking_id', class_name: "TrackingRequest", foreign_key: 'tracking_id'
  has_one :user, through: "tracking_request", class_name: "User"


  def device
    DeviceDetector.new(self.user_agent)
  end
end
