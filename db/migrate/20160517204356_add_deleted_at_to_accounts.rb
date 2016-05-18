class AddDeletedAtToAccounts < ActiveRecord::Migration
  def change
    add_column :accounts, :deleted_at, :timestamp
    add_index :accounts, :deleted_at
  end
end
