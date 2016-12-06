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

  METRIC = { NegSentiment: 0, RAGStatus: 1, PctNegSentiment: 2, DaysInactive: 3, DaysRenewal: 4, SupportVolume: 5 }
end
