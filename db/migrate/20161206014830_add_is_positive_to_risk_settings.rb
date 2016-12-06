class AddIsPositiveToRiskSettings < ActiveRecord::Migration
  def change
    add_column :risk_settings, :is_positive, :boolean, null: false, default: true
    change_column_null :risk_settings, :level_id, false
    change_column_null :risk_settings, :level_type, false
  end
end
