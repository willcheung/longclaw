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


	  def self.all_ahoy_events
	    query = <<-SQL
		    select to_char(time, 'MM/DD') as "date", cast(count(ahoy_events.*) as integer) as events
		    from ahoy_events 
		    where time > current_date - interval '14' day and not properties @> '{"page":"/settings/user_analytics"}' 
		    group by to_char(time, 'MM/DD')
		    order by "date" asc;
	    SQL
	    find_by_sql(query)
	  end

	  def self.latest_activities
	    query = <<-SQL
		    select to_char(time, 'MM/DD') as "date", ahoy_events.* as events, users.email
		    from ahoy_events
		    join users on users.id=ahoy_events.user_id 
		    where time > current_date - interval '30' day and not properties @> '{"page":"/settings/user_analytics"}' and not users.email like '%contextsmith.com'
		    group by to_char(time, 'MM/DD'), ahoy_events.id,users.email 
		    order by "date" desc;
	    SQL
	    find_by_sql(query)
	  end

  end
end
