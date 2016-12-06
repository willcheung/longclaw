class AddIsPositiveToRiskSettings < ActiveRecord::Migration
  def change
    add_column :risk_settings, :is_positive, :boolean, null: false, default: true
    change_column_null :risk_settings, :level_id, false
    change_column_null :risk_settings, :level_type, false

    reversible do |dir|
      dir.up do
        Organization.all.each do |org|
          RiskSetting.create(metric: 0, high_threshold: 80, notify_task: true, level: org)
          RiskSetting.create(metric: 1, medium_threshold: 2, high_threshold: 1, weight: 0.4, is_positive: false, level: org)
          RiskSetting.create(metric: 2, medium_threshold: 0.1, high_threshold: 0.25, weight: 0.3, level: org)
          RiskSetting.create(metric: 3, medium_threshold: 30, high_threshold: 45, weight: 0.3, level: org)
          RiskSetting.create(metric: 4, medium_threshold: 45, high_threshold: 30, weight: 0, is_positive: false, level: org)
          RiskSetting.create(metric: 5, medium_threshold: 20, high_threshold: 40, weight: 0, level: org)
        end
      end
      dir.down do
        RiskSetting.delete_all
      end
    end
  end
end
