class CreateContacts < ActiveRecord::Migration
  def change
    create_table :contacts, id: :uuid do |t|
    	t.uuid 	  :account_id
    	t.string 	:first_name,        null: false, default: ""
      t.string 	:last_name,         null: false, default: ""
      t.string 	:email,             null: false, default: ""
      t.string	:phone,							null: false, default: ""
      t.string	:title,							null: false, default: ""

      t.timestamps null: false
    end
  end
end
