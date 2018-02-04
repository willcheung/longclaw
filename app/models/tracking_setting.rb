# == Schema Information
#
# Table name: tracking_settings
#
#  id         :integer          not null, primary key
#  user_id    :uuid
#  last_seen  :datetime
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  bcc_email  :string           default("")
#  referral   :string
#

class TrackingSetting < ActiveRecord::Base
  belongs_to :user
  validates :bcc_email, email: true, allow_blank: true, allow_nil: true
  def self.find_or_create(user)
    ts = TrackingSetting.where(user: user).first_or_create do |ts|
      ts.last_seen = DateTime.now
    end
    ts.save
    ts
  end
end
