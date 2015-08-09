class ChangeProjectsDefaults < ActiveRecord::Migration
	def up
  	change_column :projects, :is_billable, :boolean, default: true
  	remove_column :projects, :sold_rate
  	rename_column :projects, :estimated_hours, :budgeted_hours
  	change_column :projects, :name, :string, null: false, default: ""
  	change_column :tasks, :name, :string, null: false, default: ""
  end

  def down
  	change_column :tasks, :name, :string, null: false, default: ""
  	change_column :projects, :name, :string, null: false, default: ""
  	add_column	:projects, :sold_rate, :integer
  	rename_column :projects, :budgeted_hours, :estimated_hours
  	change_column :projects, :is_billable, :boolean
  end
end
