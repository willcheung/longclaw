# == Schema Information
#
# Table name: custom_configurations
#
#  id              :integer          not null, primary key
#  organization_id :uuid             not null
#  user_id         :uuid
#  config_type     :string           not null
#  config_value    :string           default({}), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#
# Indexes
#
#  idx_custom_configurations  (organization_id,user_id,config_type) UNIQUE
#

##################################################################################################
# CustomConfiguration is for saving configurations that are not directly accessible in the User's Settings page
##################################################################################################

class CustomConfiguration < ActiveRecord::Base
  store :config_value, coder: JSON

  belongs_to  :organization
  belongs_to  :user

  CONFIG_TYPE = { Settings_salesforce_activities: '/settings/salesforce_activities', Salesforce_sync: 'salesforce_sync' }
  PERIOD_TYPE = { "Weekly" => {name: "Weekly", time_value: 1.week}, "Daily" => {name: "Daily", time_value: 1.day}, "Hourly" => {name: "Hourly", time_value: 1.hour} }

  scope :salesforce_sync, -> { where config_type: CONFIG_TYPE[:Salesforce_sync] }

  # Sets the custom configuration for the user or organization.  If no custom configuration was previously set for this organization, this will create and set the default configuration.  
  # Note: If both organization are user are unspecified, this will do nothing. 
  # Parameters:   user - (optional) if specified and user is non-admin, this will set the config for this user; if specified but user is an admin, this will set the config for this user's organization instead
  #               organization - (optional) if specified, this will set the config for this organization.
  #               key - (optional) "scheduled_sync", "activities", or "contacts". If this and "setDefault" parameter are both unspecified, do nothing.
  #               newValue - (optional) non-string hash value to which to set the key, e.g., {"import":"", "export":""}
  #               setDefault - (optional) if true, sets the default config. False (default).
  # Example (where current_user is an instance of a User):  CustomConfiguration.set_customconfiguration(user: current_user, key: "scheduled_sync", newValue: {CustomConfiguration::PERIOD_TYPE["Daily"][:name] => {"last_successful_run":"", "next_run":""}})
  def self.set_customconfiguration(user: nil, organization: nil, key: nil, newValue: nil, setDefault: false)
    return if (organization.blank? && user.blank?) || (user.present? && organization.present? && user.organization != organization)

    default_vals = { "scheduled_sync" => {PERIOD_TYPE["Daily"][:name] => {"last_successful_run":"", "next_run":""}}, "activities"=> {"export"=>""}, "contacts"=> {"import"=>""} }  # by default, we do not auto-export activities or contacts
    # default_vals = { "scheduled_sync" => {PERIOD_TYPE["Daily"][:name] => {"last_successful_run":"", "next_run":""}}, "activities"=> {"import"=>"","export"=>""}, "contacts"=> {"import"=>"","export"=>""} }

    if user.blank? || user.admin?
      organization ||= user.organization
      cc = organization.custom_configurations.find_or_create_by(config_type: CustomConfiguration::CONFIG_TYPE[:Salesforce_sync], user_id: nil) do |config|
        config.config_value["scheduled_sync"] = default_vals["scheduled_sync"]
        config.config_value["activities"] = default_vals["activities"]
        config.config_value["contacts"] = default_vals["contacts"] 
      end
    else
      cc = user.organization.custom_configurations.find_or_create_by(config_type: CustomConfiguration::CONFIG_TYPE[:Salesforce_sync], user_id: user.id) do |config|
        config.config_value["scheduled_sync"] = default_vals["scheduled_sync"]
        config.config_value["activities"] = default_vals["activities"]
        config.config_value["contacts"] = default_vals["contacts"]
      end
    end
    if setDefault
      cc.config_value = default_vals
    elsif key.present?
      cc.config_value[key] = newValue
    end
    cc.save
  end
end
