class AddUniqueIndexRiskSettings < ActiveRecord::Migration
  def change
    add_index :risk_settings, [:metric, :is_positive, :level_type, :level_id], unique: true, name: 'idx_risk_settings_uniq'

    reversible do |dir|
      dir.up do
        Organization.all.each do |org|
          # RiskSetting::METRIC = { NegSentiment: 0, RAGStatus: 1, PctNegSentiment: 2, DaysInactive: 3, DaysRenewal: 4, SupportVolume: 5, TotalRiskScore: 6, DaysClose: 7 }
          RiskSetting.create(metric: RiskSetting::METRIC[:DaysClose], medium_threshold: 45, high_threshold: 30, weight: 0, is_positive: false, level: org)
        end
      end
      dir.down do
        RiskSetting.where(metric: RiskSetting::METRIC[:DaysClose]).delete_all
      end
    end
  end
end
