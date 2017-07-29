class RemovePctNegSentimentDefaultRiskSetting < ActiveRecord::Migration
  def change
    # RiskSetting::METRIC = { NegSentiment: 0, RAGStatus: 1, PctNegSentiment: 2, DaysInactive: 3, DaysRenewal: 4, SupportVolume: 5, TotalRiskScore: 6, DaysClose: 7 }
    reversible do |dir|
      dir.up do
        RiskSetting.where(metric: RiskSetting::METRIC[:PctNegSentiment]).delete_all
        RiskSetting.where(metric: RiskSetting::METRIC[:RAGStatus]).update_all(weight: 0.4)
        RiskSetting.where(metric: RiskSetting::METRIC[:DaysInactive]).update_all(weight: 0.6)
      end
      dir.down do
        Organization.all.each do |org|
          RiskSetting.create(metric: RiskSetting::METRIC[:PctNegSentiment], medium_threshold: 0.1, high_threshold: 0.25, weight: 0.3, notify_task: true, level: org)
        end
        RiskSetting.where(metric: RiskSetting::METRIC[:RAGStatus]).update_all(weight: 0.4)
        RiskSetting.where(metric: RiskSetting::METRIC[:DaysInactive]).update_all(weight: 0.3)
      end
    end
  end
end
