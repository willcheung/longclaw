class CustomFieldsMetadatumController < ApplicationController
  before_action :set_custom_fields_metadata, only: [:update, :destroy]

  #Note: Probably should check if requestor has permission and visibility to view/edit a custom field.
  def create
    entity_type = CustomFieldsMetadatum.validate_and_return_entity_type(params[:entity_type])

    # Creating a metadata row will call the after_create callback and automatically create custom-field records for all existing entities
    current_user.organization.custom_fields_metadatum.create(entity_type: entity_type, name: "New field", data_type: "Text", update_permission_role: User::ROLE[:Poweruser]) if entity_type
    
    redirect_to :back  #reload page
  end

  def update
    if @custom_fields_metadata  
      respond_to do |format|
        if @custom_fields_metadata.update(custom_fields_metadatum_params)
          @custom_fields_metadata.update(custom_lists_metadatum: nil) if (@custom_fields_metadata.custom_lists_metadatum.present? && @custom_fields_metadata.data_type != CustomFieldsMetadatum::DATA_TYPE[:List])  # cannot have a custom list specified if the data_type != "List"

          @custom_fields_metadata.update(salesforce_field: nil) if @custom_fields_metadata.salesforce_field == ""  # allow straightforward best_in_place setting of salesforce_field = null

          format.html { redirect_to @custom_fields_metadata, notice: 'CustomFieldsMetadatum was successfully updated.' }
          format.js
          format.json { respond_with_bip(@custom_fields_metadata) }
        else
          format.html { render action: 'edit' }
          format.js { render json: @custom_fields_metadata.errors, status: :unprocessable_entity }
          format.json { render json: @custom_fields_metadata.errors, status: :unprocessable_entity }
        end
      end
    end
  end

  def destroy
    @custom_fields_metadata.destroy if @custom_fields_metadata

    redirect_to :back  #reload page
  end

  private

  def set_custom_fields_metadata
    @custom_fields_metadata = current_user.organization.custom_fields_metadatum.find(params[:id])
  end

  def custom_fields_metadatum_params
    params.require(:custom_fields_metadatum).permit(:name, :data_type, :update_permission_role, :custom_lists_metadata_id, :salesforce_field)
  end
end
