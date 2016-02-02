class ChangeEmailInContacts < ActiveRecord::Migration
  def change
  	change_column :contacts, :email, :string
  	change_column :contacts, :alt_email, :string

  	add_index :contacts, [:account_id]
  	add_index :projects, [:account_id]
  	add_index :project_members, [:project_id]
  	add_index :project_members, [:contact_id]
  	add_index :project_members, [:user_id]
  	add_index :activities, [:project_id]
  end
end
