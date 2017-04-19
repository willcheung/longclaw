class AddUniqueConstraintToContacts < ActiveRecord::Migration
  def change
    add_index :contacts, [:account_id, :email], unique: true
  end
end
