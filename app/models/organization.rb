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


class Organization < ActiveRecord::Base
  has_many :users, dependent: :destroy
  has_many :accounts, dependent: :destroy
  has_many :projects, through: :accounts
  has_many :contacts, through: :accounts
  has_many :oauth_users, foreign_key: "organization_id", dependent: :destroy
  has_many :salesforce_accounts, foreign_key: "contextsmith_organization_id", dependent: :destroy
  has_many :risk_settings, as: :level, dependent: :destroy
  has_many :entity_fields_metadatum, dependent: :destroy
  has_many :custom_fields_metadatum, dependent: :destroy
  has_many :custom_fields, through: :custom_fields_metadatum
  has_many :custom_lists_metadatum, dependent: :destroy
  has_many :custom_lists, through: :custom_lists_metadatum
  has_many :custom_configurations, dependent: :destroy

  scope :is_active, -> { where is_active: true }

  validates :domain, uniqueness: true

  # Returns a new Organization if there's no existing one.  If there is, return the existing one.
  def self.create_or_update_user_organization(domain, user)
    existing_org = Organization.find_by_domain(domain)

    if existing_org
      return existing_org
    else
      org_info = get_org_info(domain)
      new_org = Organization.create(name: org_info[0], domain: domain, owner_id: user.id)

      # Create default risk settings, system Custom Lists, and CS Entity fields metadata for the brand new org
      RiskSetting.create_default_for(new_org)
      CustomListsMetadatum.create_default_for(new_org)
      #EntityFieldsMetadatum.create_default_for(new_org)  # defer until connect to SFDC and visit "Settings > Salesforce Integration > Map Fields" page
      return new_org
    end
  end

  # Gets a hash of names of Custom Lists for this organization mapped to all options corresponding to each list, to be used in a Custom Lists options dropdown.  e.g., { "list1_name"=>{ "list1option1"=>"list1option1", "list1option2"=>"list1option2", ... }, "list2"=>{ "list2option1"=>"list2option1", "list2option2"=>"list2option2", ... } }
  def get_custom_lists_with_options
    customlists_w_options = {}
    self.custom_lists_metadatum.order(:name).each do |clm|
      list = {}
      clm.custom_lists.select(:option_value).index_by { |o| list[o.option_value.to_s] = o.option_value.to_s }
      customlists_w_options[clm.name] = list
    end
    return customlists_w_options
  end

  # Gets a hash of Custom List ids for this organization mapped to a short string of the list name and options, to be used in a Custom Lists dropdown.  e.g., { list1_id=>"list1_name: [list1option1, list1option2...", list2_id=>"list2_name: [list2option1, list2option2..." }
  # Parameters:  (optional) options_list_strlen_limit -- truncate and limit the length of the options string (note: the length = the options portion; square brackets and ellipsis are excluded).
  def get_custom_lists(options_list_strlen_limit=nil)
    customlists = {}
    self.custom_lists_metadatum.order(:name).index_by { |clm| customlists[clm.id] = clm.name + ": " + clm.get_list_options(options_list_strlen_limit) }
    return customlists
  end
end
