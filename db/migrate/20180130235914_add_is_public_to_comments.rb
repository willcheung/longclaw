class AddIsPublicToComments < ActiveRecord::Migration
  def change
    add_column :comments, :is_public, :boolean, default: true
  end
end
