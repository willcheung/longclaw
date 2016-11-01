class ChangePrecisionOnSfOppAmount < ActiveRecord::Migration
  def change
  	change_column :salesforce_opportunities, :amount, :decimal, :precision => 14, :scale => 2
  end
end
