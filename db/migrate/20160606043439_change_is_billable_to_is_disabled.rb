class ChangeIsBillableToIsDisabled < ActiveRecord::Migration
  def change
  	rename_column :users, :is_billable, :is_disabled
  end
end
