# == Schema Information
#
# Table name: risk_settings
#
#  id               :integer          not null, primary key
#  medium_threshold :float
#  high_threshold   :float
#  weight           :float
#  notify_task      :boolean
#  notify_email     :boolean
#  metric           :integer
#  level_id         :uuid             not null
#  level_type       :string           not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  is_positive      :boolean          default(TRUE), not null
#
# Indexes
#
#  index_risk_settings_on_level_type_and_level_id  (level_type,level_id)
#

class RiskSetting < ActiveRecord::Base
  belongs_to :level, polymorphic: true

  METRIC = { NegSentiment: 0, RAGStatus: 1, PctNegSentiment: 2, DaysInactive: 3, DaysRenewal: 4, SupportVolume: 5, TotalRiskScore: 6 }

  # Set default organization-level risk settings for a new organization
  def self.create_default_for(organization)
    create(metric: METRIC[:NegSentiment], high_threshold: 80, notify_task: true, level: organization)
    create(metric: METRIC[:RAGStatus], medium_threshold: 2, high_threshold: 1, weight: 0.4, is_positive: false, notify_task: true, level: organization)
    create(metric: METRIC[:PctNegSentiment], medium_threshold: 0.1, high_threshold: 0.25, weight: 0.3, notify_task: true, level: organization)
    create(metric: METRIC[:DaysInactive], medium_threshold: 30, high_threshold: 45, weight: 0.3, notify_task: true, level: organization)
    create(metric: METRIC[:DaysRenewal], medium_threshold: 45, high_threshold: 30, weight: 0, is_positive: false, level: organization)
    create(metric: METRIC[:SupportVolume], medium_threshold: 20, high_threshold: 40, weight: 0, level: organization)
    create(metric: METRIC[:TotalRiskScore], medium_threshold: 60, high_threshold: 80, level: organization)
  end
end
