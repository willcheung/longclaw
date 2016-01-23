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
#  is_billable            :boolean
#  created_at             :datetime
#  updated_at             :datetime
#  invitation_created_at  :datetime
#  invited_by_id          :uuid
#  onboarding_step        :integer
#  cluster_create_date    :datetime
#  cluster_update_date    :datetime
#  title                  :string
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
  has_many    :accounts
  has_many    :project_members
  has_many    :projects, through: "project_members"
  has_many    :projects_owner_of, class_name: "Project", foreign_key: "owner_id"

  devise :database_authenticatable, :registerable,
         :rememberable, :trackable, :omniauthable, :omniauth_providers => [:google_oauth2]

  validates :email, uniqueness: true

  #after_create :send_welcome_email_to_user

  PROFILE_COLOR = %w(#3C8DC5 #7D8087 #A1C436 #3cc5b9 #e58646 #1ab394 #1c84c6 #23c6c8 #f8ac59 #ed5565)

  def self.find_for_google_oauth2(auth, signed_in_resource=nil)
    info = auth.info
    credentials = auth.credentials
    user = User.where(:oauth_provider => auth.provider, :oauth_provider_uid => auth.uid ).first
    
    if user
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
          onboarding_step: Utils::ONBOARDING[:confirm_projects]
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
          onboarding_step: Utils::ONBOARDING[:confirm_projects]
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
    update_attributes(
      oauth_access_token: data['access_token'],
      oauth_expires_at: Time.now + (data['expires_in'].to_i).seconds)
  end
 
  def token_expired?
    oauth_expires_at < Time.now
  end
 
  def fresh_token
    refresh_token! if token_expired?
    oauth_access_token
  end

  #################################

  private

  def send_welcome_email_to_user
    UserMailer.welcome_email(self).deliver_later
  end

  def send_beta_teaser_email_to_user
    UserMailer.beta_teaser_email(self, "").deliver_later
  end

end
