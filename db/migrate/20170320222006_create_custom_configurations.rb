class CreateCustomConfigurations < ActiveRecord::Migration
  def change
    create_table :custom_configurations do |t|
    	t.uuid    :organization_id, null: false
    	t.uuid    :user_id
    	t.string  :config_type, null: false         # loosely related to the route
      t.string  :config_value, null: false, default: ''

      t.timestamps  null: false
    end

    # Ensure the same SF field doesn't get mapped to multiple CS entities
    add_index :custom_configurations, [:organization_id, :user_id, :config_type], :unique => true, name: 'idx_custom_configurations'
  end
end
