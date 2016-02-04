class ChangeEmailMessageDefault < ActiveRecord::Migration
  def change
    change_column :activities, :from, :jsonb, null: false, default: '[]'
    change_column :activities, :to, :jsonb, null: false, default: '[]'
    change_column :activities, :cc, :jsonb, null: false, default: '[]'
    change_column :activities, :email_messages, :jsonb, null: false, default: '[]'
  end
end
