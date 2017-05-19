# == Schema Information
#
# Table name: ahoy_events
#
#  id         :uuid             not null, primary key
#  visit_id   :uuid
#  user_id    :uuid
#  name       :string
#  properties :jsonb
#  time       :datetime
#
# Indexes
#
#  index_ahoy_events_on_time      (time)
#  index_ahoy_events_on_user_id   (user_id)
#  index_ahoy_events_on_visit_id  (visit_id)
#

module Ahoy
  class Event < ActiveRecord::Base
    self.table_name = "ahoy_events"

    belongs_to :visit
    belongs_to :user

    scope :clicks, -> { where name: "$click"}
    scope :views, -> { where name: "$view"}
    scope :changes, -> { where name: "$change"}
    scope :submits, -> { where name: "$submit"}
    scope :allow_refresh_inbox, -> { where refresh_inbox: true }


  end
end
