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


    # Get all activities last 30 days (excluding contextsmith.com) (chart, using date asc)
	  def self.all_ahoy_events
	    query = <<-SQL
		    select to_char(time, 'MM/DD') as "date", cast(count(ahoy_events.*) as integer) as events
		    from ahoy_events join users on users.id=ahoy_events.user_id 
		    where time >= current_date - interval '30' day and not properties @> '{"page":"/settings/user_analytics"}' and email not like '%contextsmith.com'
		    group by to_char(time, 'MM/DD')
		    order by "date" asc;
	    SQL
	    find_by_sql(query)
	  end

	  # DAU last 30 days (chart, using date asc)
	  def self.daily_active_users
	    query = <<-SQL
	    	select date, count(*) as dau from (
					select to_char("time", 'MM/DD') as "date", 
								users.email, 
								count(ahoy_events.properties->'page') as count 
					from ahoy_events join users on users.id=ahoy_events.user_id 
					where not properties @> '{"page":"/settings/user_analytics"}' and time >= current_date - interval '30' day and email not like '%contextsmith.com' 
					group by to_char("time", 'MM/DD'), users.email
					order by "date" asc
				) t 
				group by date
      SQL
	    find_by_sql(query)
	  end

	  # Get last 7 days of aggregate actions and pages per user (excluding contextsmith.com)
	  def self.last_14d_actions_by_page_by_user
	    query = <<-SQL
				select to_char("time", 'MM/DD') as "date", 
							users.email, 
							ahoy_events.name as action, 
							ahoy_events.properties->'page' as page, 
							count(ahoy_events.properties->'page') as count 
				from ahoy_events join users on users.id=ahoy_events.user_id 
				where not properties @> '{"page":"/settings/user_analytics"}' and not ahoy_events.name = 'gmail-extension-used' and time >= current_date - interval '7' day and email not like '%contextsmith.com' 
				group by to_char("time", 'MM/DD'), users.email, action, page 
				order by "date" desc;
      SQL
	    find_by_sql(query)
	  end

	   # Get last 14 days of aggregate activities per user (excluding contextsmith.com)
	  def self.last_14d_activities_by_user
	    query = <<-SQL
				select to_char("time", 'MM/DD') as "date", 
							users.email, 
							count(ahoy_events.properties->'page') as count 
				from ahoy_events join users on users.id=ahoy_events.user_id 
				where not properties @> '{"page":"/settings/user_analytics"}' and not ahoy_events.name = 'gmail-extension-used' and time >= current_date - interval '14' day and email not like '%contextsmith.com' 
				group by to_char("time", 'MM/DD'), users.email
				order by "date" desc;
      SQL
	    find_by_sql(query)
	  end

	  def self.companies_with_activity_last_14d
	  	query = <<-SQL
				SELECT count(distinct email) AS users_count, 
					SUBSTRING(email from '@(.*)$') AS domain
				FROM (
					select
							users.email, 
							count(ahoy_events.properties->'page') as count 
					from ahoy_events join users on users.id=ahoy_events.user_id 
					where not properties @> '{"page":"/settings/user_analytics"}' and time >= current_date - interval '14' day and SUBSTRING(email from '@(.*)$') != 'gmail.com' and email not like '%contextsmith.com'
					group by users.email
				) t
				GROUP BY domain ORDER BY users_count DESC, domain;
	  	SQL
	  	find_by_sql(query)
	  end

  end
end
