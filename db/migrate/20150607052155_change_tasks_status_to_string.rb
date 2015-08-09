class ChangeTasksStatusToString < ActiveRecord::Migration
  def change
  	change_column :tasks, :status, :string
  	rename_column	:tasks, :url, :external_url
  end
end
