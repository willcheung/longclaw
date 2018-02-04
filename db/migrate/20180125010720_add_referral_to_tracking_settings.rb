class AddReferralToTrackingSettings < ActiveRecord::Migration
  def change
    add_column :tracking_settings, :referral, :string
  end
end
