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
#  is_disabled            :boolean
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
	belongs_to 	:organization
  has_many    :accounts, foreign_key: "owner_id", dependent: :nullify
  has_many    :projects_owner_of, class_name: "Project", foreign_key: "owner_id", dependent: :nullify
  has_many    :subscriptions, class_name: "ProjectSubscriber", dependent: :destroy
  has_many    :notifications, foreign_key: "assign_to" 

  ### project_members/projects relations have 2 versions
  # v1: only shows confirmed, similar to old logic without project_members.status column
  # v2: "_all" version, ignores status
  has_many    :project_members, -> { where "project_members.status = #{ProjectMember::STATUS[:Confirmed]}" }, dependent: :destroy
  has_many    :project_members_all, class_name: "ProjectMember", dependent: :destroy
  has_many    :projects, through: "project_members"
  has_many    :projects_all, through: "project_members_all", source: :project 

  scope :registered, -> {where("users.oauth_access_token is not null or users.oauth_access_token != ''")}
  scope :not_disabled, -> {where("users.is_disabled = false")}
  scope :onboarded, -> {where("onboarding_step = #{Utils::ONBOARDING[:onboarded]}")}

  devise :database_authenticatable, :registerable,
         :rememberable, :trackable, :omniauthable, :omniauth_providers => [:google_oauth2, :salesforce, :salesforce_sandbox]

  validates :email, uniqueness: true

  # attr_encrypted :oauth_access_token

  PROFILE_COLOR = %w(#3C8DC5 #7D8087 #A1C436 #3cc5b9 #e58646 #1ab394 #1c84c6 #23c6c8 #f8ac59 #ed5565)

   def self.from_omniauth(auth, organization_id)
    where(auth.slice(:provider, :uid).permit!).first_or_initialize.tap do |user|
      oauth_user = OauthUser.find_by(oauth_instance_url: auth.credentials.instance_url, oauth_user_name: auth.extra.username, oauth_provider: auth.provider)

      if oauth_user
        oauth_user.update_attributes(oauth_access_token: auth.credentials.token,
                                     oauth_refresh_token: auth.credentials.refresh_token,
                                     oauth_instance_url: auth.credentials.instance_url,
                                     organization_id: organization_id )
      else
        oauth_user = OauthUser.create(
          oauth_provider: auth.provider,
          oauth_provider_uid: auth.uid,
          oauth_access_token: auth.credentials.token,
          oauth_refresh_token: auth.credentials.refresh_token,
          oauth_instance_url: auth.credentials.instance_url,
          oauth_user_name: auth.extra.username,
          organization_id: organization_id)

        oauth_user.save
      end
    end
  end

  def self.find_for_google_oauth2(auth, time_zone='UTC')
    info = auth.info
    credentials = auth.credentials
    user = User.where(:oauth_provider => auth.provider, :oauth_provider_uid => auth.uid ).first
    
    if user
      if credentials["refresh_token"].nil? or credentials["refresh_token"].empty?
        user.update_attributes(oauth_access_token: credentials["token"], 
                               oauth_expires_at: Time.at(credentials["expires_at"]),
                               time_zone: time_zone)
      else
        user.update_attributes(oauth_access_token: credentials["token"], 
                               oauth_expires_at: Time.at(credentials["expires_at"]),
                               oauth_refresh_token: credentials["refresh_token"],
                               time_zone: time_zone)
      end
      return user
    else
      # Considered referred user if email exists but not oauth elements
      referred_user = User.where(:email => auth.info.email).first

      if referred_user
        # Change referred_user into real user
        referred_user.update_attributes(
          first_name: info["first_name"],
          last_name: info["last_name"],
          oauth_provider: auth.provider,
          email: info["email"],
          image_url: info["image"],
          oauth_provider_uid: auth.uid,
          password: Devise.friendly_token[0,20],
          oauth_access_token: credentials["token"],
          oauth_refresh_token: credentials["refresh_token"],
          oauth_expires_at: Time.at(credentials["expires_at"]),
          onboarding_step: Utils::ONBOARDING[:fill_in_info],
          is_disabled: false,
          time_zone: time_zone
        )

        return referred_user
      else # New User
        user = User.create(
          first_name: info["first_name"],
        	last_name: info["last_name"],
          oauth_provider: auth.provider,
          email: info["email"],
          image_url: info["image"],
          oauth_provider_uid: auth.uid,
          password: Devise.friendly_token[0,20],
          oauth_access_token: credentials["token"],
          oauth_refresh_token: credentials["refresh_token"],
          oauth_expires_at: Time.at(credentials["expires_at"]),
          onboarding_step: Utils::ONBOARDING[:fill_in_info],
          is_disabled: false,
          time_zone: time_zone
        )
        
        org = Organization.create_or_update_user_organization(get_domain(info["email"]), user)
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

  def self.count_activities_by_user(array_of_account_ids, domain, time_zone='UTC')
    query = <<-SQL
      select t2.inbound as email,
             t2.inbound_count, 
             COALESCE(t1.outbound_count,0) as outbound_count, 
             COALESCE(t1.outbound_count,0)+COALESCE(t2.inbound_count,0) as total 
      from
        (select "from" as outbound, 
                count(DISTINCT message_id) as outbound_count 
          from user_activities_last_14d 
          where "from" like '%#{domain}' and to_timestamp(sent_date::integer) AT TIME ZONE '#{time_zone}' BETWEEN (CURRENT_DATE AT TIME ZONE '#{time_zone}' - INTERVAL '14 days') and (CURRENT_DATE AT TIME ZONE '#{time_zone}') and project_id in (SELECT id as project_id from projects where account_id in ('#{array_of_account_ids.join("','")}'))
          group by "from" order by outbound_count desc) t1
      FULL OUTER JOIN 
        (select inbound, count(DISTINCT message_id) as inbound_count from 
          (
            select "to" as inbound, message_id from user_activities_last_14d where "to" like '%#{domain}' UNION ALL select "cc" as inbound, message_id from user_activities_last_14d 
            where "cc" like '%#{domain}' and to_timestamp(sent_date::integer) AT TIME ZONE '#{time_zone}' BETWEEN (CURRENT_DATE AT TIME ZONE '#{time_zone}' - INTERVAL '14 days') and (CURRENT_DATE AT TIME ZONE '#{time_zone}') and project_id in (SELECT id as project_id from projects where account_id in ('#{array_of_account_ids.join("','")}'))
          ) t
        group by inbound order by inbound_count desc) t2
        ON t1.outbound = t2.inbound
        order by total desc
        limit 10;
    SQL

    User.find_by_sql(query)
  end

  # Team Leaderboard chart
  def self.count_activities_by_user_flex(array_of_account_ids, domain, start_day=14.days.ago.midnight.utc, end_day=Time.current.end_of_day.utc)
    date_range = "TIMESTAMP '#{start_day}' AND TIMESTAMP '#{end_day}'"
    query = <<-SQL
      -- email_activities extracts the activity info from the email_messages jsonb in activities, based on the email_activities_last_14d view
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
          AND to_timestamp((messages ->> 'sentDate')::integer) BETWEEN #{date_range}
          AND project_id IN 
          (
            SELECT id AS project_id 
            FROM projects 
            WHERE account_id IN ('#{array_of_account_ids.join("','")}')
          )
          GROUP BY 1,2,3,4
        )
      SELECT t2.inbound AS email,
             t2.inbound_count, 
             COALESCE(t1.outbound_count,0) AS outbound_count, 
             COALESCE(t1.outbound_count,0)+COALESCE(t2.inbound_count,0) AS total 
      FROM
      -- t1 counts all emails sent by each user (specified in "from" field) in the provided domain in the last 14 days across all accounts in the organization
        (
          SELECT "from" AS outbound, 
                count(DISTINCT message_id) AS outbound_count 
          FROM email_activities 
          WHERE "from" LIKE '%#{domain}'
          GROUP BY "from" ORDER BY outbound_count DESC
        ) t1
      FULL OUTER JOIN 
      -- t2 counts all emails received by each user in the provided domain in the last 14 days across all accounts in the organization
        (
          SELECT inbound, count(DISTINCT message_id) AS inbound_count FROM 
          -- t collects all emails received by each user (specified in either "to" or "cc" fields) in the provided domain in the last 14 days across all accounts in the organization
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

  def is_internal_user?
    true
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
      puts "Warning: access_token nil while refreshing token for user #{email}"
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
