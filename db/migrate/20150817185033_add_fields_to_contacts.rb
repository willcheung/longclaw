class AddFieldsToContacts < ActiveRecord::Migration
  def change
  		add_column :contacts, :alt_email, :string, limit: 64
  		change_column :contacts, :email, :string, limit: 64
  		add_column :contacts, :mobile, :string, limit: 32
  		change_column :contacts, :phone, :string, limit: 32
  		add_column :contacts, :background_info, :text
  		add_column :contacts, :department, :string
  end
end
