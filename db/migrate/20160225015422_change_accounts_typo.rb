class ChangeAccountsTypo < ActiveRecord::Migration
  def change
  	rename_column :accounts, :cateogry, :category
  end
end
