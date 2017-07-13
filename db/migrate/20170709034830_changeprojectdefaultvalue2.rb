class Changeprojectdefaultvalue2 < ActiveRecord::Migration
  def change
    change_column_default :projects, :category, "New Business"
  end
end
