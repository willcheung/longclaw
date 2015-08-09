class CreateProjects < ActiveRecord::Migration
  def change
    create_table :projects, id: :uuid do |t|
      t.string  :name
      t.uuid    :account_id
      t.string  :project_code
      t.boolean :is_billable
      t.string  :status
      t.text    :description
      t.date    :planned_start_date
      t.date    :planned_end_date
      t.date    :actual_start_date
      t.date    :actual_end_date
      t.integer :estimated_hours
      t.integer	:sold_rate
      t.uuid    :created_by
      t.uuid    :updated_by
      t.uuid    :owner_id
      t.boolean :is_template, :default => false

      t.timestamps null: false
    end
  end
end
