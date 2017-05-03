class AddExternalSourceIdToContacts < ActiveRecord::Migration
  def change
		add_column :contacts, :external_source_id, :string
  end
end
