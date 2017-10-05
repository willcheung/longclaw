class AddBccToTrackingSetting < ActiveRecord::Migration
  def change
    add_column :tracking_settings, :bcc_email, :string, default: ''
  end
end
