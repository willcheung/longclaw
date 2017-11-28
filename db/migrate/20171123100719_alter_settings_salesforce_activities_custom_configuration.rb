class AlterSettingsSalesforceActivitiesCustomConfiguration < ActiveRecord::Migration
  def change
    CustomConfiguration.where("config_type like '/settings/salesforce_activities#%'").destroy_all
    reversible do |dir|
      dir.up do
    		CustomConfiguration.where(config_type: 'salesforce_refresh').update_all(config_type: CustomConfiguration::CONFIG_TYPE[:Salesforce_sync])
      end
      dir.down do
    		CustomConfiguration.where(config_type: CustomConfiguration::CONFIG_TYPE[:Salesforce_sync]).update_all(config_type: 'salesforce_refresh')
      end
    end
  end
end
