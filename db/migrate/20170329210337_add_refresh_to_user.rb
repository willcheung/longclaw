class AddRefreshToUser < ActiveRecord::Migration
  def change
  	add_column :users, :refresh_inbox, :boolean, :default => true, null: false
  	change_column :users, :is_disabled, :boolean, :default => false, null: false

  	User.update_all(refresh_inbox: true)
  	User.update_all(is_disabled: false)
  end
end
