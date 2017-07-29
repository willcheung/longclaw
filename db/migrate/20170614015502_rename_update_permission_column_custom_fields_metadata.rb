class RenameUpdatePermissionColumnCustomFieldsMetadata < ActiveRecord::Migration
  def change
    rename_column :custom_fields_metadata, :update_permission_level, :update_permission_role  # User::ROLE
  end
end
