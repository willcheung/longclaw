# == Schema Information
#
# Table name: organizations
#
#  id         :uuid             not null, primary key
#  name       :string
#  domain     :string
#  is_active  :boolean          default(TRUE)
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  owner_id   :uuid
#

class Organization < ActiveRecord::Base
  has_many :users
  has_many :accounts
  has_many :oauth_users, foreign_key: "organization_id"
  has_many :salesforce_accounts, foreign_key: "contextsmith_organization_id"
  has_many :risk_settings, as: :level

  validates :domain, uniqueness: true

  # Returns new_org if there's no existing one.  If there is, return existing one.
  def self.create_or_update_user_organization(domain, user)
    existing_org = Organization.find_by_domain(domain)

    if existing_org
      return existing_org
    else
      org_info = get_org_info(domain)
      new_org = Organization.create(name: org_info[0], domain: domain, owner_id: user.id)

      RiskSetting.create_default_for(new_org)
      return new_org
    end
  end
end
