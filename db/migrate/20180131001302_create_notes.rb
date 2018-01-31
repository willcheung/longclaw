class CreateNotes < ActiveRecord::Migration
  def self.up
    create_table :notes do |t|
      t.string :title, :limit => 50, :default => "" 
      t.text   :note, null:false
      t.string  :noteable_type, null:false, index:true
      t.uuid    :noteable_uuid, null:false, index:true  # FK
      t.uuid    :user_uuid, null:false, index:true
      t.boolean :is_public, default:false

      t.timestamps null: false
    end
  end

  def self.down
    drop_table :notes
  end
end
