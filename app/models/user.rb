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
#  hourly_rate            :integer
#  is_billable            :boolean
#  created_at             :datetime
#  updated_at             :datetime
#
# Indexes
#
#  index_users_on_email                 (email) UNIQUE
#  index_users_on_reset_password_token  (reset_password_token) UNIQUE
#

class User < ActiveRecord::Base
	belongs_to 	:organization
	has_many		:projects
  has_many    :accounts

  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :trackable, :validatable, :omniauthable

  #after_create :send_welcome_email_to_user
  #after_create :send_beta_teaser_email_to_user
  after_create :create_user_organization

  def self.find_for_google_oauth2(auth, signed_in_resource=nil)
    info = auth.info
    credentials = auth.credentials
    user = User.where(:oauth_provider => auth.provider, :oauth_provider_uid => auth.uid ).first
    
    if user
      return user
    else
      registered_user = User.where(:email => auth.info.email).first
      if registered_user
        return registered_user
      else
        user = User.create(
          first_name: info["first_name"],
        	last_name: info["last_name"],
          oauth_provider:auth.provider,
          email: info["email"],
          image_url: info["image"],
          oauth_provider_uid: auth.uid,
          password: Devise.friendly_token[0,20],
          oauth_access_token: credentials["token"],
          oauth_refresh_token: credentials["refresh_token"],
          oauth_expires_at: Time.at(credentials["expires_at"])
        )
      end
    end
  end

  private

  def send_welcome_email_to_user
    UserMailer.welcome_email(self).deliver_later
  end

  def send_beta_teaser_email_to_user
    UserMailer.beta_teaser_email(self, "").deliver_later
  end

  def create_user_organization
    # Creates seperate organization for users even if they have the same domain
  end
end
