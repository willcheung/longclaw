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
  has_many :oauth_users
  has_many :salesforce_accounts, foreign_key: "contextsmith_organization_id"
  has_many :risk_settings, as: :level
  has_many :custom_fields_metadatum
  has_many :custom_fields #, through: :custom_fields_metadatum
  has_many :custom_lists_metadatum
  has_many :custom_lists, through: :custom_lists_metadatum

  validates :domain, uniqueness: true

  # Returns new_org if there's no existing one.  If there is, return existing one.
  def self.create_or_update_user_organization(domain, user)
    existing_org = Organization.find_by_domain(domain)

    if existing_org
      return existing_org
    else
      org_info = get_org_info(domain)
      new_org = Organization.create(name: org_info[0], domain: domain, owner_id: user.id)

      # Create default settings and custom lists for the brand new org
      RiskSetting.create_default_for(new_org)
      CustomListsMetadatum.create_default_for(new_org)
      return new_org
    end
  end

  # Gets a hash of names of custom lists for this organization mapped to all options corresponding to each list, to be used in a dropdown (e.g., { "list1" => { "list1option1"=>"list1option1", ... }, "list2" => { "list2option1"=>"list2option1", ... }})
  def get_custom_lists_with_options
    customlists_w_options = {}
    self.custom_lists_metadatum.order(:cs_app_list, :created_at).each do |clm|
      list = {}
      clm.custom_lists.select(:option_value).index_by { |o| list[o.option_value.to_s] = o.option_value.to_s }
      customlists_w_options[clm.name] = list
    end
    return customlists_w_options
  end

  # Gets a hash of names of custom lists for this organization mapped to all options corresponding to each list, to be used in a dropdown (e.g., { "list1" => { "list1option1"=>"list1option1", ... }, "list2" => { "list2option1"=>"list2option1", ... }})
  def get_custom_lists
    customlists = {}
    self.custom_lists_metadatum.order(:cs_app_list, :created_at).index_by { |clm| customlists[clm.id] = clm.name }
    return customlists
  end
end
