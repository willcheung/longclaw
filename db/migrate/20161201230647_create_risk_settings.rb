class CreateRiskSettings < ActiveRecord::Migration
  def change
    create_table :risk_settings do |t|
      t.float :medium_threshold
      t.float :high_threshold
      t.float :weight
      t.boolean :notify_task
      t.boolean :notify_email
      t.integer :metric
      t.uuid :level_id
      t.string :level_type

      t.timestamps null: false
    end

    add_index :risk_settings, [:level_type, :level_id]
  end
end
