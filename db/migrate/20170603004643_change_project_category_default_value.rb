class ChangeProjectCategoryDefaultValue < ActiveRecord::Migration
  def change
    change_column_default :projects, :category, "Opportunity"
  end
end
