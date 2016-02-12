class AddCateogryToAccount < ActiveRecord::Migration
  def change
  	add_column :accounts, :cateogry, :string, :default => "Customer"
  	add_column :projects, :category, :string, :default => "Project"
  	change_column :accounts, :status, :string, :default => "Active"
  	change_column :projects, :status, :string, :default => "Active"
  end
end
