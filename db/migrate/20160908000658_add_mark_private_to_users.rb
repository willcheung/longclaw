class AddMarkPrivateToUsers < ActiveRecord::Migration
  def change
  	add_column :users, :mark_private, :boolean, :default => false, null: false

  	User.update_all(mark_private: false)

  end
end
