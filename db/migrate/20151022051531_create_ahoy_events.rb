class CreateAhoyEvents < ActiveRecord::Migration
  def change
    create_table :ahoy_events, id: false do |t|
      t.uuid :id, default: nil, primary_key: true
      t.uuid :visit_id, default: nil

      # user
      t.uuid :user_id
      # add t.string :user_type if polymorphic

      t.string :name
      t.jsonb :properties
      t.timestamp :time
    end

    add_index :ahoy_events, [:visit_id]
    add_index :ahoy_events, [:user_id]
    add_index :ahoy_events, [:time]
  end
end
