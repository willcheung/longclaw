class RemoveNameAndDomainMappableFieldsMeta < ActiveRecord::Migration
  def change
    reversible do |dir|
      dir.up do
        Organization.all.each do |org|
          EntityFieldsMetadatum.create_default_for(org) if org.entity_fields_metadatum.first.present?  # discards all existing mapping (including any fields we wish to exclude) and creates a new mapping set
        end
      end
      dir.down do
      	# Don't undo any mapping
      end
    end
  end
end
