# == Schema Information
#
# Table name: tracking_settings
#
#  id         :integer          not null, primary key
#  user_id    :uuid
#  last_seen  :datetime
#  created_at :datetime         not null
#  updated_at :datetime         not null
#

class TrackingSetting < ActiveRecord::Base
  belongs_to :user
end
