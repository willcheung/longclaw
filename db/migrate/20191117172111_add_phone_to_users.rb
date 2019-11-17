class AddPhoneToUsers < ActiveRecord::Migration
  def change
  	change_column :users, :email, :string, null: true, default: nil
  	add_column :users, :phone, :string
  end
end
