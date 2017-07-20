class AddSalesforceFieldToCustomFieldsMetadata < ActiveRecord::Migration
  def change
  	# Change name of default value column to avoid SQL syntax ambiguity and simplify future SQL statements
    rename_column :custom_fields_metadata, :default, :default_value

    # Add a new column that will store the mapping between Salesforce entity field/column to CS entity field/column
    add_column :custom_fields_metadata, :salesforce_field, :string

    # Ensure the same SF field doesn't get mapped to multiple CS entities
    add_index :custom_fields_metadata, [:organization_id, :entity_type, :salesforce_field], :unique => true, name: 'idx_custom_fields_metadata_on_sf_field_and_entity_unique'
  end
end
