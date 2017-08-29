# == Schema Information
#
# Table name: tracking_requests
#
#  id          :integer          not null, primary key
#  user_id     :uuid
#  message_id  :string(255)
#  recipients  :text             default([]), is an Array
#  status      :string
#  sent_at     :datetime
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  tracking_id :string(255)
#  subject     :string
#  email_id    :string
#

class TrackingRequest < ActiveRecord::Base
  belongs_to :user
  has_many :tracking_events, :primary_key => "tracking_id", :foreign_key => "tracking_id", :class_name => "TrackingEvent"
           -> { order(date: :desc) }

  def recipients_to_list
    if self.recipients.count > 1
      'one of the recipients (' + self.recipients.join(', ') + ')'
    else
      self.recipients.join('') # also good for case where recipients is null or empty
    end

  end

  def toggle_status
    self.status = self.status == 'active' ? 'inactive' : 'active'
  end
end
