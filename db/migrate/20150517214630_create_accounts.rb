class CreateAccounts < ActiveRecord::Migration
  def change
    create_table :accounts, id: :uuid do |t|
      t.string	:name, null: false, default: ""
      t.text		:description, default: ""
      t.string	:website
      t.uuid	  :owner_id
      t.string	:phone
      t.text		:address
      t.uuid  	:created_by
      t.uuid  	:updated_by

      t.timestamps null: false
    end
  end
end
