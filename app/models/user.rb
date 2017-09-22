# == Schema Information
#
# Table name: users
#
#  id                     :uuid             not null, primary key
#  first_name             :string           default(""), not null
#  last_name              :string           default(""), not null
#  email                  :string           default(""), not null
#  encrypted_password     :string           default(""), not null
#  image_url              :string
#  reset_password_token   :string
#  reset_password_sent_at :datetime
#  remember_created_at    :datetime
#  sign_in_count          :integer          default(0), not null
#  current_sign_in_at     :datetime
#  last_sign_in_at        :datetime
#  current_sign_in_ip     :inet
#  last_sign_in_ip        :inet
#  oauth_provider         :string
#  oauth_provider_uid     :string
#  oauth_access_token     :string
#  oauth_refresh_token    :string
#  oauth_expires_at       :datetime
#  organization_id        :uuid
#  department             :string
#  is_disabled            :boolean          default(FALSE), not null
#  created_at             :datetime
#  updated_at             :datetime
#  invitation_created_at  :datetime
#  invited_by_id          :uuid
#  onboarding_step        :integer
#  cluster_create_date    :datetime
#  cluster_update_date    :datetime
#  title                  :string
#  time_zone              :string           default("UTC")
#  mark_private           :boolean          default(FALSE), not null
#  role                   :string
#  refresh_inbox          :boolean          default(TRUE), not null
#  encrypted_password_iv  :string
#
# Indexes
#
#  index_users_on_email                 (email) UNIQUE
#  index_users_on_reset_password_token  (reset_password_token) UNIQUE
#

require 'net/http'
require 'json'
include Utils
include ContextSmithParser

class User < ActiveRecord::Base
  belongs_to  :organization
  has_many    :accounts, foreign_key: "owner_id", dependent: :nullify
  has_many    :projects_owner_of, -> { is_active }, class_name: "Project", foreign_key: "owner_id", dependent: :nullify
  has_many    :subscriptions, class_name: "ProjectSubscriber", dependent: :destroy
  has_many    :notifications, -> { non_attachments }, foreign_key: "assign_to", dependent: :nullify
  has_many    :notifications_all, foreign_key: "assign_to", class_name: 'Notification', dependent: :destroy
  has_many    :attachments, -> { attachments }, foreign_key: "assign_to", class_name: 'Notification'
  has_many    :oauth_users
  has_many    :custom_configurations, dependent: :destroy
  has_many    :events
  has_many    :tracking_requests, dependent: :destroy
  has_one     :tracking_setting, dependent: :destroy


  ### project_members/projects relations have 2 versions
  # v1: only shows confirmed, similar to old logic without project_members.status column
  # v2: "_all" version, ignores status
  has_many    :project_members, -> { confirmed }, dependent: :destroy, class_name: 'ProjectMember'
  has_many    :project_members_all, class_name: "ProjectMember", dependent: :destroy
  has_many    :projects, through: "project_members"
  has_many    :projects_all, through: "project_members_all", source: :project

  scope :registered, -> { where.not encrypted_password: '' } # ecrypted_password is set for all registered users, whether they auth through google_oauth2 or exchange_pwd
  scope :not_disabled, -> { where is_disabled: false }
  scope :allow_refresh_inbox, -> { where refresh_inbox: true }
  scope :onboarded, -> { where onboarding_step: Utils::ONBOARDING[:onboarded] }
  scope :exchange_auth, -> { where oauth_provider: AUTH_TYPE[:Exchange] }
  scope :ordered_by_first_name, -> { order('LOWER(first_name) ASC') }

  devise :database_authenticatable, :registerable, :oathkeeper_authenticatable,
         :rememberable, :trackable, :omniauthable, :omniauth_providers => [:google_oauth2, :google_oauth2_basic, :salesforce, :salesforce_sandbox]

  validates :email, uniqueness: true

  # attr_encrypted :oauth_access_token
  attr_encrypted :password, key: ENV['encryption_key'], if: proc { |user| user.oauth_provider == User::AUTH_TYPE[:Exchange] }

  PROFILE_COLOR = %w(#3C8DC5 #7D8087 #A1C436 #3cc5b9 #e58646 #1ab394 #1c84c6 #23c6c8 #f8ac59 #ed5565)
  ROLE = { Admin: 'Admin', Poweruser: 'Power user', Contributor: 'Contributor', Observer: 'Observer', Basic: 'Basic', Pro: 'Professional', Biz: 'Business' }
  OTHER_ROLE = { Trial: 'Trial', Chromeuser: "Chrome user" }  # TODO: remove "Chrome user"
  AUTH_TYPE = { Gmail: 'google_oauth2', Exchange: 'exchange_pwd' }
  WORDS_PER_SEC = { Read: 2.0, Write: 0.42 }   # Reading=120WPM(<200)  Typing=~25WPM(<40)
  #WORDS_PER_HOUR = { Read: 4000.0, Write: 900.0 }
  ATTACHMENT_TIME_SEC = 60*9

  def valid_streams_subscriptions
    self.subscriptions.joins(:project).where(projects: {id: Project.visible_to(self.organization_id, self.id).pluck(:id)})
  end

  # this calls the backend which in turn queries the data sources (like GMail etc.) for each call
  def upcoming_meetings
    visible_projects = Project.visible_to(organization_id, id)

    meetings_in_cs = Activity.where(category: Activity::CATEGORY[:Meeting], last_sent_date: (Time.current..1.day.from_now), project_id: visible_projects.ids)
      .where("\"from\" || \"to\" || \"cc\" @> '[{\"address\":\"#{email}\"}]'::jsonb").order(:last_sent_date)
    return meetings_in_cs unless registered?

    # time adjustments for repeating meetings which have last_sent_date as the creation time of the meeting
    # remove again when Oathkeeper is fixed
    calendar_meetings = ContextsmithService.load_calendar_for_user(self).each do |a|
      a.last_sent_date = Time.current.midnight + a.last_sent_date.hour.hours + a.last_sent_date.min.minutes
      a.last_sent_date += 1.day if a.last_sent_date < Time.current
    end.sort_by(&:last_sent_date)

    # merge calendar_meetings with meetings_in_cs
    meetings_in_cs.each do |mic|
      # find matching meetings between meetings_in_cs and calendar_meetings based on backend_id
      i = calendar_meetings.index { |cm| cm.backend_id == mic.backend_id }
      if i.nil?
        # no match found, insert the meeting_in_cs in the right place
        i = calendar_meetings.index { |cm| cm.last_sent_date > mic.last_sent_date }
        i = -1 if i.nil?
        calendar_meetings.insert(i, mic)
      else
        # match found, replace the calendar_meeting with the meeting_in_cs, but use the time from calendar_meeting and update it in DB
        mic.update(last_sent_date: calendar_meetings[i].last_sent_date, last_sent_date_epoch: calendar_meetings[i].last_sent_date_epoch, email_messages: calendar_meetings[i].email_messages)
        calendar_meetings[i] = mic
      end
    end

    calendar_meetings
  end

  def self.from_omniauth(auth, organization_id, user_id=nil)
    where(auth.slice(:provider, :uid).permit!).first_or_initialize.tap do |user|
      if user_id
        oauth_user = OauthUser.find_by(oauth_instance_url: auth.credentials.instance_url, oauth_user_name: auth.extra.username, oauth_provider: auth.provider, organization_id: organization_id, user_id: user_id)
      else
        oauth_user = OauthUser.find_by(oauth_instance_url: auth.credentials.instance_url, oauth_user_name: auth.extra.username, oauth_provider: auth.provider, organization_id: organization_id)
      end

      if oauth_user
        if user_id
          oauth_user.update_attributes(oauth_access_token: auth.credentials.token,
                                       oauth_refresh_token: auth.credentials.refresh_token,
                                       oauth_instance_url: auth.credentials.instance_url,
                                       organization_id: organization_id,
                                       user_id: user_id )
        else
          oauth_user.update_attributes(oauth_access_token: auth.credentials.token,
                                       oauth_refresh_token: auth.credentials.refresh_token,
                                       oauth_instance_url: auth.credentials.instance_url,
                                       organization_id: organization_id)
        end
      else
        if user_id
          oauth_user = OauthUser.create(
            oauth_provider: auth.provider,
            oauth_provider_uid: auth.uid,
            oauth_access_token: auth.credentials.token,
            oauth_refresh_token: auth.credentials.refresh_token,
            oauth_instance_url: auth.credentials.instance_url,
            oauth_user_name: auth.extra.username,
            organization_id: organization_id,
            user_id: user_id)
        else
          oauth_user = OauthUser.create(
            oauth_provider: auth.provider,
            oauth_provider_uid: auth.uid,
            oauth_access_token: auth.credentials.token,
            oauth_refresh_token: auth.credentials.refresh_token,
            oauth_instance_url: auth.credentials.instance_url,
            oauth_user_name: auth.extra.username,
            organization_id: organization_id)
        end

        oauth_user.save
      end
    end
  end

  def self.find_for_google_oauth2(auth, time_zone='UTC', params)
    info = auth.info
    credentials = auth.credentials
    user = User.find_by(oauth_provider: auth.provider, oauth_provider_uid: auth.uid )

    if user
      user_attributes = {
        oauth_access_token: credentials.token,
        oauth_expires_at: Time.at(credentials.expires_at),
        time_zone: time_zone
      }
      user_attributes[:oauth_refresh_token] = credentials.refresh_token if credentials.refresh_token.present?
      user.update_attributes(user_attributes)
      user
    else
      # Considered referred user if e-mail exists but not oauth elements
      referred_user = User.find_by_email(info.email)
      user_attributes = {
        first_name: info.first_name || '',
        last_name: info.last_name || '',
        oauth_provider: auth.provider,
        email: info.email,
        image_url: info.image,
        oauth_provider_uid: auth.uid,
        password: Devise.friendly_token[0,20],
        oauth_access_token: credentials.token,
        oauth_refresh_token: credentials.refresh_token,
        oauth_expires_at: Time.at(credentials.expires_at),
        onboarding_step: Utils::ONBOARDING[:fill_in_info],
        role: ROLE[:Basic],
        is_disabled: false,
        refresh_inbox: false,
        time_zone: time_zone
      }
      user_attributes[:role] = params['role'] if params['role']

      if referred_user
        # Change referred_user into real user
        referred_user.update_attributes(user_attributes)

        return referred_user
      else # New User
        user = User.create(user_attributes)
        domain = info.email.include?('gmail.com') ? info.email : get_domain(info.email)

        org = Organization.create_or_update_user_organization(domain, user)
        user.update_attributes(organization_id: org.id)

        return user
      end
    end
  end

  def self.create_from_clusters(internal_members, invited_by_id, organization_id)
    internal_emails = internal_members.map(&:address)

    internal_members.each do |m|
      u = User.create(
        first_name: get_first_name(m.personal),
        last_name: get_last_name(m.personal),
        email: m.address,
        organization_id: organization_id,
        invited_by_id: invited_by_id,
        invitation_created_at: Time.now
      )
    end
  end

  def self.confirm_projects_for_user(user)
    return -1 if user.onboarding_step == Utils::ONBOARDING[:onboarded]

    return_vals = {}
    overlapping_projects = []
    new_projects = []
    same_projects = []

    custom_lists = user.organization.get_custom_lists_with_options
    return_vals[:account_types] = !custom_lists.blank? ? custom_lists["Account Type"] : {}
    
    new_user_projects = Project.where(created_by: user.id, is_confirmed: false).includes(:users, :contacts, :account)
    all_accounts = user.organization.accounts.includes(projects: [:users, :contacts])

    new_user_projects.each do |new_project|
      new_project_members = new_project.contacts.map(&:email).map(&:downcase).map(&:strip)

      all_accounts.each do | account |
        if account.id == new_project.account.id
          overlapping_p = []
          new_p = []
          same_p = []

          # puts "---Account is " + account.name + "---\n"
          # puts "Projects in this account: " + account.projects.size.to_s

          if account.projects.empty?
            # This account has no project, so new_project is considered first project.
            new_p << new_project if !new_p.include?(new_project)
          else
            account.projects.each do |existing_project|
              existing_project_members = existing_project.contacts.map(&:email).map(&:downcase).map(&:strip)
              
              # DEBUG MSG
              # puts existing_project_members
              # puts "----"
              # puts new_project_members

              dc = dice_coefficient(existing_project_members, new_project_members)
              intersect = intersect(existing_project_members, new_project_members)
              puts "Dice Coefficient #{dc}, Intersect #{intersect}"

              if dc == 1.0
                # 100% match in external members. Do not display these projects.
                same_p << existing_project
              elsif dc < 1.0 and dc > 0.0
                # Considered same project. 
                overlapping_p << existing_project
              # elsif dc < 0.2 and dc > 0.0 and intersect > 1
              #   # Considered existing projects because there are more than 1 shared members.
              #   overlapping_p << existing_project
              # elsif dc < 0.2 and dc > 0.0 and intersect == 1
              #   # This is likely a one-time communication or a typo by e-mail sender.

              #   # If the existing project already has current user, then likely this conversation is part of that project.
              #   if existing_project.users.map(&:email).include?(user.email)
              #     overlapping_p << existing_project
              #   else
              #     new_p << new_project if !new_p.include?(new_project)
              #   end
              else dc == 0.0 
                # Definitely new project.  Modify new project into confirmed project.
                new_p << new_project if !new_p.include?(new_project)
              end
            end #account.projects.each do |existing_project|
          end #if account.projects.empty?

          # Take action on the unconfirmed projects
          if account.projects.size == 0
            # Add project into account.  Modify new project into confirmed project
            new_project.update_attributes(is_confirmed: true)
          elsif overlapping_p.size > 0
            overlapping_p.each do |p|
              p.project_members.create(user_id: user.id)

              # Copy new_project contacts and users
              new_project.contacts.each do |c|
                p.project_members.create(contact_id: c.id)
              end

              new_project.users.each do |u|
                p.project_members.create(user_id: u.id)
              end

              # Copy new_project activities
              Activity.copy_email_activities(new_project, p)
            end

            new_project.destroy # Delete unconfirmed project

          else # No overlapping projects
            if same_p.size > 0
              same_p.each do |p|
                p.project_members.create(user_id: user.id)

                # Copy new_project activities
                Activity.copy_email_activities(new_project, p)

                # Subscribe to existing project
                p.subscribers.create(user_id: user.id)
              end

              new_project.destroy # Delete unconfirmed project
              
            elsif new_p.size > 0
              new_project.update_attributes(is_confirmed: true)
              # Subscribe to existing project
              new_project.subscribers.create(user_id: user.id)
            end
          end

          # Prepare projects for View
          overlapping_p.each { |p| overlapping_projects << p }
          new_p.each { |p| new_projects << p }
          same_p.each { |p| same_projects << p }
        end #if account.id == new_project.account.id
      end #all_accounts.each do | account |
    end #new_user_projects.each do |new_project|

    return_vals[:project_last_email_date] = Project.visible_to(user.organization_id, user.id).includes(:activities).where("activities.category = 'Conversations'").maximum("activities.last_sent_date")
    
    # Change user onboarding flag
    user.update_attributes(onboarding_step: Utils::ONBOARDING[:onboarded])

    # Return values to caller
    return_vals[:overlapping_projects] = overlapping_projects
    return_vals[:new_projects] = new_projects
    return_vals[:same_projects] = same_projects

    return_vals[:result] = 0  # success
    return return_vals
  end

  def daily_activities_by_category(time_zone, start_day=14.days.ago.midnight.utc, end_day=Time.current.end_of_day.utc)
    array_of_account_ids = self.organization.accounts.ids
    array_of_project_ids = Project.where(account_id: array_of_account_ids).ids
    query = <<-SQL
      WITH time_series AS (
        SELECT generate_series(date(TIMESTAMP '#{start_day}'), date(TIMESTAMP '#{end_day}'), INTERVAL '1 day') AS days LIMIT #{(end_day - start_day).ceil / 86400}
      )
      (
      SELECT date(time_series.days) AS days, '#{Activity::CATEGORY[:Conversation]}' AS category, COUNT(DISTINCT emails.message_id) AS num_activities
      FROM time_series
      LEFT JOIN (SELECT to_timestamp((messages ->> 'sentDate')::integer) AS sent_date,
                        messages ->> 'messageId'::text AS message_id,
                       jsonb_array_elements(messages -> 'from') ->> 'address' AS from,
                       CASE
                         WHEN messages -> 'to' IS NULL THEN NULL
                         ELSE jsonb_array_elements(messages -> 'to') ->> 'address'
                       END AS to,
                       CASE
                         WHEN messages -> 'cc' IS NULL THEN NULL
                         ELSE jsonb_array_elements(messages -> 'cc') ->> 'address'
                       END AS cc
                FROM activities,
                LATERAL jsonb_array_elements(email_messages) messages
                WHERE category = '#{Activity::CATEGORY[:Conversation]}'
                AND project_id IN ('#{array_of_project_ids.join("','")}')
                AND (messages ->> 'sentDate')::integer BETWEEN #{start_day.to_i} AND #{end_day.to_i}
          ) AS emails
        ON (date_trunc('day', emails.sent_date AT TIME ZONE '#{time_zone}') = time_series.days)
        AND #{User.sanitize(self.email)} IN (emails.from, emails.to, emails.cc)
      GROUP BY days, category
      ORDER BY days ASC
      )
      UNION ALL
      (
      -- Meetings directly from activities table
      SELECT date(time_series.days) AS days, '#{Activity::CATEGORY[:Meeting]}' AS category, count(meetings.*) AS num_activities
      FROM time_series
      LEFT JOIN (SELECT last_sent_date AS sent_date, project_id
                  FROM activities 
                  WHERE category = '#{Activity::CATEGORY[:Meeting]}' 
                  AND "from" || "to" || "cc" @> ('[{"address": "' || #{User.sanitize(self.email)} || '"}]')::jsonb 
                  AND project_id IN ('#{array_of_project_ids.join("','")}')
                  AND EXTRACT(EPOCH FROM last_sent_date) BETWEEN '#{start_day.to_i}' AND '#{end_day.to_i}'
                ) AS meetings
        ON date_trunc('day', meetings.sent_date AT TIME ZONE 'UTC' AT TIME ZONE '#{time_zone}') = time_series.days
      GROUP BY days, category
      ORDER BY days ASC
      )
      UNION ALL
      (
      -- JIRA directly from activities table
      SELECT date(time_series.days) AS days, '#{Activity::CATEGORY[:JIRA]}' AS category, count(jiras.*) AS num_activities
      FROM time_series
      LEFT JOIN (SELECT last_sent_date AS sent_date, project_id
                  FROM activities 
                  WHERE category = '#{Activity::CATEGORY[:JIRA]}' 
                  AND "from" || "to" || "cc" @> ('[{"address": "' || #{User.sanitize(self.email)} || '"}]')::jsonb 
                  AND project_id IN ('#{array_of_project_ids.join("','")}')
                  AND EXTRACT(EPOCH FROM last_sent_date) BETWEEN '#{start_day.to_i}' AND '#{end_day.to_i}'
                ) AS jiras
        ON date_trunc('day', jiras.sent_date AT TIME ZONE 'UTC' AT TIME ZONE '#{time_zone}') = time_series.days
      GROUP BY days, category
      ORDER BY days ASC
      )
      UNION ALL
      (
      -- Salesforce directly from activities table
      SELECT date(time_series.days) AS days, '#{Activity::CATEGORY[:Salesforce]}' AS category, count(salesforces.*) AS num_activities
      FROM time_series
      LEFT JOIN (SELECT last_sent_date AS sent_date, project_id
                  FROM activities 
                  WHERE category = '#{Activity::CATEGORY[:Salesforce]}' 
                  AND "from" || "to" || "cc" @> ('[{"address": "' || #{User.sanitize(self.email)} || '"}]')::jsonb 
                  AND project_id IN ('#{array_of_project_ids.join("','")}')
                  AND EXTRACT(EPOCH FROM last_sent_date) BETWEEN '#{start_day.to_i}' AND '#{end_day.to_i}'
                ) AS salesforces
        ON date_trunc('day', salesforces.sent_date AT TIME ZONE 'UTC' AT TIME ZONE '#{time_zone}') = time_series.days
      GROUP BY days, category
      ORDER BY days ASC
      )
      UNION ALL
      (
      -- Zendesk directly from activities table
      SELECT date(time_series.days) AS days, '#{Activity::CATEGORY[:Zendesk]}' AS category, count(zendesks.*) AS num_activities
      FROM time_series
      LEFT JOIN (SELECT last_sent_date AS sent_date, project_id
                  FROM activities 
                  WHERE category = '#{Activity::CATEGORY[:Zendesk]}' 
                  AND "from" || "to" || "cc" @> ('[{"address": "' || #{User.sanitize(self.email)} || '"}]')::jsonb 
                  AND project_id IN ('#{array_of_project_ids.join("','")}')
                  AND EXTRACT(EPOCH FROM last_sent_date) BETWEEN '#{start_day.to_i}' AND '#{end_day.to_i}'
                ) AS zendesks
        ON date_trunc('day', zendesks.sent_date AT TIME ZONE 'UTC' AT TIME ZONE '#{time_zone}') = time_series.days
      GROUP BY days, category
      ORDER BY days ASC
      )
      UNION ALL
      (
      -- Basecamp2 directly from activities table
      SELECT date(time_series.days) AS days, '#{Activity::CATEGORY[:Basecamp2]}' AS category, count(basecamp2s.*) AS num_activities
      FROM time_series
      LEFT JOIN (SELECT last_sent_date AS sent_date, project_id
                  FROM activities 
                  WHERE category = '#{Activity::CATEGORY[:Basecamp2]}' 
                  AND "from" || "to" || "cc" @> ('[{"address": "' || #{User.sanitize(self.email)} || '"}]')::jsonb 
                  AND project_id IN ('#{array_of_project_ids.join("','")}')
                  AND EXTRACT(EPOCH FROM last_sent_date) BETWEEN '#{start_day.to_i}' AND '#{end_day.to_i}'
                ) AS basecamp2s
        ON date_trunc('day', basecamp2s.sent_date AT TIME ZONE 'UTC' AT TIME ZONE '#{time_zone}') = time_series.days
      GROUP BY days, category
      ORDER BY days ASC
      )  
      UNION ALL
      (
      -- Sent Attachments directly from notifications table
      SELECT date(time_series.days) AS days, '#{Notification::CATEGORY[:Attachment]}' AS category, count(attachments.*) AS num_activities
      FROM time_series
      LEFT JOIN (SELECT sent_date, project_id
                  FROM notifications 
                  WHERE category = '#{Notification::CATEGORY[:Attachment]}' 
                  AND description::jsonb->'from'->0->>'address' = #{User.sanitize(self.email)} 
                  AND project_id IN ('#{array_of_project_ids.join("','")}')
                  AND EXTRACT(EPOCH FROM sent_date AT TIME ZONE '#{self.time_zone}') > EXTRACT(EPOCH FROM TIMESTAMP '#{start_day}')
                ) AS attachments
        ON date_trunc('day', attachments.sent_date AT TIME ZONE 'UTC' AT TIME ZONE '#{self.time_zone}') = time_series.days
      GROUP BY days, category
      ORDER BY days ASC
      )
    SQL

    User.find_by_sql(query)
  end

  # Team Leaderboard chart
  def self.count_activities_by_user_flex(array_of_account_ids, domain, start_day=14.days.ago.midnight.utc, end_day=Time.current.end_of_day.utc)
    query = <<-SQL
      -- email_activities extracts the activity info from the email_messages jsonb in activities
      WITH email_activities AS
        (
          SELECT messages ->> 'messageId'::text AS message_id,
                 jsonb_array_elements(messages -> 'from') ->> 'address' AS from,
                 CASE
                   WHEN messages -> 'to' IS NULL THEN NULL
                   ELSE jsonb_array_elements(messages -> 'to') ->> 'address'
                 END AS to,
                 CASE
                   WHEN messages -> 'cc' IS NULL THEN NULL
                   ELSE jsonb_array_elements(messages -> 'cc') ->> 'address'
                 END AS cc
          FROM activities,
          LATERAL jsonb_array_elements(email_messages) messages
          WHERE category = 'Conversation'
          AND to_timestamp((messages ->> 'sentDate')::integer) BETWEEN TIMESTAMP '#{start_day}' AND TIMESTAMP '#{end_day}'
          AND project_id IN
          (
            SELECT id AS project_id
            FROM projects
            WHERE account_id IN ('#{array_of_account_ids.join("','")}')
          )
          GROUP BY 1,2,3,4
        )
      SELECT COALESCE(t2.inbound, t1.outbound) AS email,
             COALESCE(t2.inbound_count,0) AS inbound_count,
             COALESCE(t1.outbound_count,0) AS outbound_count,
             COALESCE(t1.outbound_count,0)+COALESCE(t2.inbound_count,0) AS total
      FROM
      -- t1 counts all e-mails sent by each user (specified in "from" field) in the provided domain in the last 14 days across all accounts in the organization
        (
          SELECT "from" AS outbound, count(DISTINCT message_id) AS outbound_count
          FROM email_activities
          WHERE "from" LIKE '%#{domain}'
          GROUP BY "from" ORDER BY outbound_count DESC
        ) t1
      FULL OUTER JOIN
      -- t2 counts all e-mails received by each user in the provided domain in the last 14 days across all accounts in the organization
        (
          SELECT inbound, count(DISTINCT message_id) AS inbound_count FROM
          -- t collects all e-mails received by each user (specified in either "to" or "cc" fields) in the provided domain in the last 14 days across all accounts in the organization
          (
            SELECT "to" AS inbound, message_id FROM email_activities WHERE "to" LIKE '%#{domain}'
            UNION ALL
            SELECT "cc" AS inbound, message_id FROM email_activities WHERE "cc" LIKE '%#{domain}'
          ) t
          GROUP BY inbound ORDER BY inbound_count DESC
        ) t2
      ON t1.outbound = t2.inbound
      ORDER BY total DESC
    SQL

    User.find_by_sql(query)
  end

  # Count of number of activities for accounts in array_of_account_ids, and for users in array_of_user_ids, and between a range of days (default=last 14d)
  def self.count_all_activities_by_user(array_of_project_ids, array_of_user_ids, start_day=14.days.ago.midnight.utc, end_day=Time.current.end_of_day.utc)
    return [] if array_of_project_ids.blank? || array_of_user_ids.blank?
    query = <<-SQL
      (
        SELECT users.id, 'E-mails Received' AS category, COUNT(DISTINCT emails.message_id) AS num_activities
        FROM users
        LEFT JOIN (
          SELECT messages ->> 'messageId'::text AS message_id,
                 jsonb_array_elements(messages -> 'from') ->> 'address' AS from,
                 CASE
                   WHEN messages -> 'to' IS NULL THEN NULL
                   ELSE jsonb_array_elements(messages -> 'to') ->> 'address'
                 END AS to,
                 CASE
                   WHEN messages -> 'cc' IS NULL THEN NULL
                   ELSE jsonb_array_elements(messages -> 'cc') ->> 'address'
                 END AS cc
          FROM activities,
          LATERAL jsonb_array_elements(email_messages) messages
          WHERE category = '#{Activity::CATEGORY[:Conversation]}'
          AND to_timestamp((messages ->> 'sentDate')::integer) BETWEEN TIMESTAMP '#{start_day}' AND TIMESTAMP '#{end_day}'
          AND project_id IN ('#{array_of_project_ids.join("','")}')
        ) AS emails
        ON (users.email IN (emails.to, emails.cc) AND users.email NOT IN (emails.from))
        WHERE users.id IN ('#{array_of_user_ids.join("','")}')
        GROUP BY users.id, category
      )
      UNION ALL
      (
        SELECT users.id, 'E-mails Sent' AS category, COUNT(DISTINCT emails.message_id) AS num_activities
        FROM users
        LEFT JOIN (
          SELECT messages ->> 'messageId'::text AS message_id,
                 jsonb_array_elements(messages -> 'from') ->> 'address' AS from,
                 CASE
                   WHEN messages -> 'to' IS NULL THEN NULL
                   ELSE jsonb_array_elements(messages -> 'to') ->> 'address'
                 END AS to,
                 CASE
                   WHEN messages -> 'cc' IS NULL THEN NULL
                   ELSE jsonb_array_elements(messages -> 'cc') ->> 'address'
                 END AS cc
          FROM activities,
          LATERAL jsonb_array_elements(email_messages) messages
          WHERE category = '#{Activity::CATEGORY[:Conversation]}'
          AND to_timestamp((messages ->> 'sentDate')::integer) BETWEEN TIMESTAMP '#{start_day}' AND TIMESTAMP '#{end_day}'
          AND project_id IN ('#{array_of_project_ids.join("','")}')
        ) AS emails
        ON users.email IN (emails.from)
        WHERE users.id IN ('#{array_of_user_ids.join("','")}')
        GROUP BY users.id, category
      )
      UNION ALL
      (
        SELECT users.id, '#{Activity::CATEGORY[:Meeting]}' AS category, COUNT(activities.*) AS num_activities
        FROM users
        LEFT JOIN activities
        ON category = '#{Activity::CATEGORY[:Meeting]}'
        AND ("from" || "to" || "cc") @> ('[{"address":"' || users.email || '"}]')::jsonb
        AND last_sent_date BETWEEN TIMESTAMP '#{start_day}' AND TIMESTAMP '#{end_day}'
        AND project_id IN ('#{array_of_project_ids.join("','")}')
        WHERE users.id IN ('#{array_of_user_ids.join("','")}')
        GROUP BY users.id, category
      )
      UNION ALL
      (
        SELECT users.id, '#{Activity::CATEGORY[:JIRA]}' AS category, COUNT(activities.*) AS num_activities
        FROM users
        LEFT JOIN activities
        ON category = '#{Activity::CATEGORY[:JIRA]}'
        AND ("from" || "to" || "cc") @> ('[{"address":"' || users.email || '"}]')::jsonb
        AND last_sent_date BETWEEN TIMESTAMP '#{start_day}' AND TIMESTAMP '#{end_day}'
        AND project_id IN ('#{array_of_project_ids.join("','")}')
        WHERE users.id IN ('#{array_of_user_ids.join("','")}')
        GROUP BY users.id, category
      )
      UNION ALL
      (
        SELECT users.id, '#{Activity::CATEGORY[:Zendesk]}' AS category, COUNT(activities.*) AS num_activities
        FROM users
        LEFT JOIN activities
        ON category = '#{Activity::CATEGORY[:Zendesk]}'
        AND ("from" || "to" || "cc") @> ('[{"address":"' || users.email || '"}]')::jsonb
        AND last_sent_date BETWEEN TIMESTAMP '#{start_day}' AND TIMESTAMP '#{end_day}'
        AND project_id IN ('#{array_of_project_ids.join("','")}')
        WHERE users.id IN ('#{array_of_user_ids.join("','")}')
        GROUP BY users.id, category
      )
      UNION ALL
      (
        SELECT users.id, '#{Activity::CATEGORY[:Salesforce]}' AS category, COUNT(activities.*) AS num_activities
        FROM users
        LEFT JOIN activities
        ON category = '#{Activity::CATEGORY[:Salesforce]}'
        AND ("from" || "to" || "cc") @> ('[{"address":"' || users.email || '"}]')::jsonb
        AND last_sent_date BETWEEN TIMESTAMP '#{start_day}' AND TIMESTAMP '#{end_day}'
        AND project_id IN ('#{array_of_project_ids.join("','")}')
        WHERE users.id IN ('#{array_of_user_ids.join("','")}')
        GROUP BY users.id, category
      )
      UNION ALL
      (
        SELECT users.id, '#{Activity::CATEGORY[:Basecamp2]}' AS category, COUNT(activities.*) AS num_activities
        FROM users
        LEFT JOIN activities
        ON category = '#{Activity::CATEGORY[:Basecamp2]}'
        AND ("from" || "to" || "cc") @> ('[{"address":"' || users.email || '"}]')::jsonb
        AND last_sent_date BETWEEN TIMESTAMP '#{start_day}' AND TIMESTAMP '#{end_day}'
        AND project_id IN ('#{array_of_project_ids.join("','")}')
        WHERE users.id IN ('#{array_of_user_ids.join("','")}')
        GROUP BY users.id, category
      )
      UNION ALL
      -- Sent Attachments
      (
        SELECT users.id, '#{Notification::CATEGORY[:Attachment]}' AS category, COUNT(notifications.*) AS num_activities
        FROM users
        LEFT JOIN notifications
        ON category = '#{Notification::CATEGORY[:Attachment]}'
        AND description::jsonb->'from'->0->>'address' = users.email
        AND sent_date BETWEEN TIMESTAMP '#{start_day}' AND TIMESTAMP '#{end_day}'
        AND project_id IN ('#{array_of_project_ids.join("','")}')
        WHERE users.id IN ('#{array_of_user_ids.join("','")}')
        GROUP BY users.id, category
      )
    SQL

    User.find_by_sql(query)
  end

  def self.team_usage_report(array_of_project_ids, array_of_user_emails, start_day=14.days.ago.midnight.utc, end_day=Time.current.end_of_day.utc)
    query = <<-SQL
      -- email_activities extracts the activity info from the email_messages jsonb in activities
      -- shows the total time usage be adding all the inbound e-mails and outbound e-mails as inbound and outbound
      WITH email_activities AS (
        SELECT  messages ->> 'messageId'::text AS message_id,
                jsonb_array_elements(messages -> 'from') ->> 'address' AS from,
          CASE
             WHEN messages -> 'to' IS NULL THEN NULL
             ELSE jsonb_array_elements(messages -> 'to') ->> 'address'
          END AS to,
          CASE
             WHEN messages -> 'cc' IS NULL THEN NULL
             ELSE jsonb_array_elements(messages -> 'cc') ->> 'address'
          END AS cc,
          (messages::json ->'content') ->> 'body'  AS body,
          array_length(regexp_split_to_array((messages::json ->'content') ->> 'body',E'[^\\\\w:!.()?//\\\\,-]+'),1) AS word_count
        FROM activities,
        LATERAL jsonb_array_elements(email_messages) messages
        WHERE category='Conversation'
          AND to_timestamp((messages ->> 'sentDate')::integer) BETWEEN TIMESTAMP '#{start_day}' AND TIMESTAMP '#{end_day}'
          AND project_id IN ('#{array_of_project_ids.join("','")}')
        GROUP BY 1,2,3,4,5
      ), outbound AS (
        SELECT sender, count(distinct message_id) num_messages, SUM(word_count) as total_wc
        FROM (
          SELECT distinct "from" AS sender, message_id, word_count 
          FROM email_activities
          WHERE "from" IN (#{array_of_user_emails.map{|u| User.sanitize(u)}.join(',')})
        ) AS o
        GROUP BY sender
      ), inbound AS (
        SELECT recipient, count(distinct message_id) num_messages, SUM(word_count) as total_wc
        FROM (
          SELECT distinct "to" AS recipient, message_id, word_count
          FROM email_activities
          WHERE "to" IN (#{array_of_user_emails.map{|u| User.sanitize(u)}.join(',')})
            AND "to" != "from"
          UNION
          SELECT distinct "cc", message_id, word_count from email_activities
          WHERE "cc" IN (#{array_of_user_emails.map{|u| User.sanitize(u)}.join(',')})
            AND "cc" != "from"
        ) AS i
        GROUP BY recipient
      ), conversation_members AS (
        SELECT sender AS email FROM outbound
        UNION
        SELECT recipient FROM inbound 
      )
      SELECT c.email, COALESCE(o.total_wc,0) AS outbound, COALESCE(i.total_wc,0) AS inbound, COALESCE(o.total_wc,0)+COALESCE(i.total_wc,0) AS total
      FROM conversation_members AS c
      --WHERE email IN (#{array_of_user_emails.map{|u| User.sanitize(u)}.join(',')})
      LEFT JOIN outbound AS o 
      ON o.sender = c.email
      LEFT JOIN inbound AS i
      ON i.recipient = c.email
      ORDER BY total DESC, outbound DESC
      limit 5;
    SQL
    find_by_sql(query)
  end

  def email_time_by_project(array_of_project_ids=Project.visible_to(self.organization_id, self.id).pluck(:id), start_day=14.days.ago.midnight.utc, end_day=Time.current.end_of_day.utc)  # array_of_user_emails
    query = <<-SQL
      WITH user_emails AS (
        SELECT messages ->> 'messageId'::text AS message_id,
               project_id,
               array_length(regexp_split_to_array((messages ->'content') ->> 'body', E'[^\\\\w:!.()?//\\\\,-]+'), 1) AS word_count,
               jsonb_array_elements(messages -> 'from') ->> 'address' AS from,
               CASE
                 WHEN messages -> 'to' IS NULL THEN NULL
                 ELSE jsonb_array_elements(messages -> 'to') ->> 'address'
               END AS to,
               CASE
                 WHEN messages -> 'cc' IS NULL THEN NULL
                 ELSE jsonb_array_elements(messages -> 'cc') ->> 'address'
               END AS cc
        FROM activities,
        LATERAL jsonb_array_elements(email_messages) messages
        WHERE category = '#{Activity::CATEGORY[:Conversation]}'
        AND project_id IN ('#{array_of_project_ids.join("','")}')
        AND to_timestamp((messages ->> 'sentDate')::integer) BETWEEN TIMESTAMP '#{start_day}' AND TIMESTAMP '#{end_day}'
      )
      SELECT projects.id, projects.name, SUM(outbound_wc)::float AS outbound, SUM(inbound_wc)::float AS inbound, COALESCE(SUM(outbound_wc),0) + COALESCE(SUM(inbound_wc),0) AS total
      FROM (
        SELECT outbound_emails.project_id, SUM(outbound_emails.word_count) AS outbound_wc, 0 AS inbound_wc
        FROM (
          SELECT DISTINCT message_id, project_id, word_count
          FROM user_emails
          WHERE "from" = #{User.sanitize(self.email)}
        ) outbound_emails
        GROUP BY project_id, message_id
        UNION ALL
        SELECT inbound_emails.project_id, 0 AS outbound_wc, SUM(inbound_emails.word_count) AS inbound_wc
        FROM (
          SELECT DISTINCT message_id, project_id, word_count
          FROM user_emails
          WHERE #{User.sanitize(self.email)} IN ("to", "cc")
            AND #{User.sanitize(self.email)} NOT IN ("from")
        ) inbound_emails
        GROUP BY project_id, message_id
      ) AS wc_table
      INNER JOIN projects
      ON projects.id = wc_table.project_id
      GROUP BY 1
      ORDER BY total
    SQL
    project_times = Project.find_by_sql(query)

    project_times.each do |p|
      p.inbound = (p.inbound / WORDS_PER_SEC[:Read]).round
      p.outbound = (p.outbound / WORDS_PER_SEC[:Write]).round
    end
  end

  def self.meeting_report(array_of_project_ids, array_of_user_emails, start_day=14.days.ago.midnight.utc, end_day=Time.current.end_of_day.utc)
    query = <<-SQL
      WITH user_meeting AS(
        SELECT  "to" AS attendees, email_messages AS end_epoch, last_sent_date_epoch AS start_epoch, backend_id
          FROM activities,
          LATERAL jsonb_array_elements(email_messages) messages
          WHERE category = '#{Activity::CATEGORY[:Meeting]}'
          AND EXTRACT(EPOCH FROM last_sent_date) BETWEEN #{start_day.to_i} AND #{end_day.to_i}  -- based on meeting start time, not end time!
          AND project_id IN ('#{array_of_project_ids.join("','")}')
        GROUP BY 1,2,3,4
      )
      SELECT email, SUM(end_t::integer - start_t::integer) AS total -- duration
      FROM (
        SELECT email, start_t, end_t, backend_id
        FROM(   
            SELECT jsonb_array_elements(attendees) ->> 'address' AS email,
                  start_epoch AS start_t,
                  jsonb_array_elements(end_epoch) ->> 'end_epoch' AS end_t,
                  backend_id
            FROM user_meeting ) t
        WHERE email in (#{array_of_user_emails.map{|u| User.sanitize(u)}.join(',')})
        GROUP BY backend_id, t.email, t.start_t, t.end_t ) as t2
        GROUP BY t2.email
        ORDER BY total DESC;
    SQL
  find_by_sql(query)
  end

  def meeting_time_by_project(array_of_project_ids=Project.visible_to(self.organization_id, self.id).pluck(:id), start_day=14.days.ago.midnight.utc, end_day=Time.current.end_of_day.utc) # array_of_user_emails
    query = <<-SQL
      SELECT projects.id, projects.name, SUM((messages->>'end_epoch')::integer - last_sent_date_epoch::integer)::float AS total_meeting_hours
      FROM activities
      INNER JOIN projects
      ON projects.id = activities.project_id,
      LATERAL jsonb_array_elements(email_messages) messages
      WHERE activities.category = '#{Activity::CATEGORY[:Meeting]}'
      AND EXTRACT(EPOCH FROM last_sent_date) BETWEEN #{start_day.to_i} AND #{end_day.to_i}
      AND "from" || "to" || cc @> ('[{"address":"' || #{User.sanitize(self.email)} || '"}]')::jsonb
      AND project_id IN ('#{array_of_project_ids.join("','")}')
      GROUP BY 1
    SQL
    Project.find_by_sql(query)
  end

  def self.sent_attachments_count(array_of_project_ids, array_of_user_emails, start_day=13.days.ago.midnight.utc, end_day=Time.current.end_of_day.utc)
    query = <<-SQL
      WITH user_attachments AS (
        SELECT message_id, description::jsonb->'from'->0->>'address' AS sender
        FROM notifications
        WHERE category = '#{Notification::CATEGORY[:Attachment]}'
        AND sent_date AT TIME ZONE 'UTC' BETWEEN TIMESTAMP '#{start_day}' AND TIMESTAMP '#{end_day}'
        AND project_id IN('#{array_of_project_ids.join("','")}')
        GROUP BY 1,2
      )
      SELECT sender AS email, COUNT(message_id) AS attachment_count
      FROM user_attachments
      WHERE sender IN (#{array_of_user_emails.map { |u| sanitize(u) }.join(',')})
      GROUP BY 1
    SQL
    find_by_sql(query)
  end

  def sent_attachments_by_project(array_of_project_ids=Project.visible_to(self.organization_id, self.id).pluck(:id), start_day=13.days.ago.midnight.utc, end_day=Time.current.end_of_day.utc) # array_of_user_emails
    query = <<-SQL
      SELECT projects.id, projects.name, COUNT(DISTINCT message_id) AS attachment_count
      FROM projects
      JOIN notifications
      ON projects.id = notifications.project_id
      AND notifications.category = '#{Notification::CATEGORY[:Attachment]}'
      AND notifications.sent_date AT TIME ZONE 'UTC' BETWEEN TIMESTAMP '#{start_day}' AND TIMESTAMP '#{end_day}'
      AND notifications.description::jsonb->'from'->0->>'address' = #{User.sanitize(email)}
      AND projects.id IN ('#{array_of_project_ids.join("','")}')
      GROUP BY 1,2
    SQL
    Project.find_by_sql(query)
  end

  # Returns a map of the ROLEs values only (not keys), for use in best-in-place picklists
  def self.getRolesMap(include_other_roles=false)
    roles_map = {}
    ROLE.each do |r| #self.ROLE.each do |clm|
      roles_map[r[1]] = r[1]
    end
    OTHER_ROLE.each do |r| #self.ROLE.each do |clm|
      roles_map[r[1]] = r[1]
    end if include_other_roles
    return roles_map
  end

  def upgrade(role)
    self.role = ROLE[role]
  end

  ######### Basic ACL ##########
  # Roles have cascading effect, e.g. if you're an "admin", then you also have access to what other roles have.  
  # Note: The member helpers below is used to determine if the user has access to the appropriate features of that role level ("has_rolelevel_access?".  e.g., "admin?" means user has access to the appropriate features of the Admin role level ("has_admin_access?"); similarly, "power_user?" = user has access to features that a power user may access ("has_power_user_access?"), which implies admin also can access this too.

  def admin?
    self.role == ROLE[:Admin]
  end

  def power_user?
    self.role == ROLE[:Poweruser] || self.admin?
  end

  def contributor?
    self.role == ROLE[:Contributor] || self.power_user?
  end

  def observer?
    self.role == ROLE[:Observer] || self.contributor?
  end

  def biz?
    self.role == ROLE[:Biz] || self.observer?
  end

  def pro?
    self.role == ROLE[:Pro] || self.biz?
  end

  def basic?
    self.role == ROLE[:Basic] || self.pro?
  end

  def trial?
    self.role == OTHER_ROLE[:Trial]
  end

  # Trial user = Chrome User (TODO: remove "Chrome user")
  def power_or_trial_only?
    [ROLE[:Poweruser], OTHER_ROLE[:Chromeuser], OTHER_ROLE[:Trial]].include? (self.role) 
  end

  def superadmin?
    %w(wcheung@contextsmith.com will@context-smith.com beders@contextsmith.com klu@contextsmith.com vluong@contextsmith.com syong@contextsmith.com chobbs@contextsmith.com craig@context-smith.com churst@contextsmith.com).include?(self.email)
  end

  ######### End Basic ACL ##########

  def is_internal_user?
    true
  end

  # ecrypted_password is set for all registered users, whether they auth through google_oauth2 or exchange_pwd
  def registered?
    encrypted_password.present?
  end

  # Oauth Helper Methods
  # https://www.twilio.com/blog/2014/09/gmail-api-oauth-rails.html
  def to_params
    {'refresh_token' => oauth_refresh_token,
    'client_id' => ENV['google_client_id'],
    'client_secret' => ENV['google_client_secret'],
    'grant_type' => 'refresh_token'}
  end

  def request_token_from_google
    url = URI("https://www.googleapis.com/oauth2/v3/token")
    Net::HTTP.post_form(url, self.to_params)
  end

  def refresh_token!
    response = request_token_from_google
    data = JSON.parse(response.body)

    if data['access_token'].nil?
      puts "Access_token nil while refreshing token for user #{email}"
      update_attributes(oauth_access_token: "invalid")
      return false
    else
      update_attributes(
        oauth_access_token: data['access_token'],
        oauth_expires_at: Time.now + (data['expires_in'].to_i).seconds)
      return true
    end
  end

  def token_expired?
    oauth_expires_at < Time.now
  end

  def fresh_token
    refresh_token! if token_expired?
    oauth_access_token
  end

end
