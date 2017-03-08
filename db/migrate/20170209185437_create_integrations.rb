class CreateIntegrations < ActiveRecord::Migration
  def change
    create_table :integrations do |t|
      t.uuid :contextsmith_account_id
      t.integer :external_account_id
      t.uuid :project_id
      t.string :external_source

      t.timestamps null: false
    end
  end
end
