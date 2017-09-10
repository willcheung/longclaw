# == Schema Information
#
# Table name: tracking_requests
#
#  id          :integer          not null, primary key
#  user_id     :uuid
#  tracking_id :string
#  message_id  :string(255)
#  subject     :string
#  recipients  :text             default([]), is an Array
#  status      :string
#  sent_at     :datetime
#  email_id    :string
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
# Indexes
#
#  index_tracking_requests_on_tracking_id  (tracking_id)
#

class TrackingRequest < ActiveRecord::Base
  belongs_to :user
  has_many :tracking_events, :primary_key => "tracking_id", :foreign_key => "tracking_id", :class_name => "TrackingEvent"
           -> { order(date: :desc) }

  scope :from_lastmonth, -> { where sent_at: 1.month.ago.midnight..Time.current }
  scope :has_recipients, -> (email_array) { where "'{#{ email_array.map{|e| Contact.sanitize(e.downcase)}.map{|e| e[1...e.size-1]}.join(",") }}'::text[] && recipients" }

  def recipients_to_list
    self.recipients.join(', ')
  end

  def someone
    if self.recipients.count > 1
      'one of the recipients (' + self.recipients.join(', ') + ')'
    else
      self.recipients.join('')
    end

  end

  def toggle_status
    self.status = self.status == 'active' ? 'inactive' : 'active'
  end
end
