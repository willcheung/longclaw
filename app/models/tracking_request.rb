# == Schema Information
#
# Table name: tracking_requests
#
#  id          :integer          not null, primary key
#  user_id     :uuid
#  message_id  :string
#  recipients  :text             default([]), is an Array
#  status      :string
#  sent_at     :datetime
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  tracking_id :string
#  subject     :string
#  email_id    :string
#
# Indexes
#
#  index_tracking_requests_on_tracking_id  (tracking_id)
#  index_tracking_requests_on_user_id      (user_id)
#

class TrackingRequest < ActiveRecord::Base
  belongs_to :user
  has_many :tracking_events, :primary_key => "tracking_id", :foreign_key => "tracking_id", :class_name => "TrackingEvent"
           -> { order(date: :desc) }

  scope :from_lastmonth, -> { where sent_at: 1.month.ago.midnight..Time.current }
  scope :where_by_any_recipient, -> (email_array) { where "'{#{ email_array.map{|e| Contact.sanitize(e.downcase)}.map{|e| e[1...e.size-1]}.join(",") }}'::text[] && recipients" }

  def self.find_by_any_recipient(email_array)
    begin
      where_by_any_recipient(email_array).load
    rescue => e
      puts "**** Error while running TrackingRequest.find_by_any_recipient(#{email_array}):\nException: #{e.to_s}\n****"
    end
  end

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
