# == Schema Information
#
# Table name: organizations
#
#  id                 :uuid             not null, primary key
#  name               :string
#  domain             :string
#  is_active          :boolean          default(TRUE)
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  owner_id           :uuid
#  billing_email      :string
#  stripe_customer_id :string
#  plan_id            :string
#

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
      user.save if user.new_record?
      new_org = Organization.create(name: org_info[0], domain: domain, owner_id: user.id)

      # Create default risk settings and system Custom Lists for the brand new org
      RiskSetting.create_default_for(new_org)
      CustomListsMetadatum.create_default_for(new_org)
      return new_org
    end
  end


  # Sets the custom configuration for the user or this organization.  If no custom configuration was previously set for this organization, this will create and set the default configuration.  
  # Note: If user is unspecified, we will attempt to set this organization's config. 
  # Parameters:   user - (optional) if specified and user is non-admin, this will set the config for this user; if specified but user is an admin, this will set the config for this user's organization instead. If unspecified, this will set config for this organization.
  #               key - (optional) "scheduled_sync", "activities", or "contacts". If this and "setDefault" parameter are both unspecified, do nothing.
  #               newValue - (optional) non-string hash value to which to set the key, e.g., {"import":"", "export":""}
  #               setDefault - (optional) if true, sets the default config. False (default).
  # Examples (where org1 is an instance of an Organization, user1 is an instance of a User in org1):
  #   - org1.set_customconfiguration(setDefault: true)  # => sets default configuration for this organization (org1)
  #   - org1.set_customconfiguration(user: user1, key: "scheduled_sync", newValue: {CustomConfiguration::PERIOD_TYPE["Daily"][:name] => {"last_successful_run":"", "next_run":""}})  # ==> enables daily refresh for user1 and org1
  def set_customconfiguration(user: nil, key: nil, newValue: nil, setDefault: false)
    return if user.organization != self

    if user.blank? || user.admin?
      CustomConfiguration.set_customconfiguration(organization: self, key: key, newValue: newValue, setDefault: setDefault)
    else
      CustomConfiguration.set_customconfiguration(user: user, key: key, newValue: newValue, setDefault: setDefault)
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

  ### TODO: To consider custom "Closed Won"/"Closed Lost" stages, use native SFDC fields is_closed and is_won instead
  def get_winning_stages
    ['Closed Won', 'Closed and Signed']  # hard-coded until we do it dynamically from SFDC data
  end

  def get_losing_stages
    ['Closed Lost'] # hard-coded until we do it dynamically from SFDC data
  end

  def get_closed_stages
    get_winning_stages + get_losing_stages
  end
end
