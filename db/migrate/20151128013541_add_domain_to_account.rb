class AddDomainToAccount < ActiveRecord::Migration
  def change
  	add_column :accounts, :domain, :string, limit: 64, null: false, default: ""
  	remove_column :projects, :is_template, :boolean
  	remove_column :users, :hourly_rate, :integer
  end
end
