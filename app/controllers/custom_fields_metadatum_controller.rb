class CustomFieldsMetadatumController < ApplicationController
  #Note: Probably should check if requestor has permission and visibility to view/edit a custom field.
  def create
    entity_type = CustomFieldsMetadatum.validate_and_return_entity_type(params[:entity_type])

    # Creating a metadata row will call the after_create callback and automatically create custom-field records for all existing entities
    current_user.organization.custom_fields_metadatum.create(entity_type:entity_type, name:"New field", data_type:"Text", update_permission_level:User::ROLE[:Contributor]) if entity_type
    
    redirect_to :back  #reload page
  end

  def update
    custom_fields_metadata = current_user.organization.custom_fields_metadatum.find(params[:id])
    if custom_fields_metadata  
      respond_to do |format|
        if custom_fields_metadata.update(custom_fields_metadatum_params)
          if not custom_fields_metadata.custom_lists_metadatum.nil? and custom_fields_metadata.data_type != CustomFieldsMetadatum::DATA_TYPE[:List]
            custom_fields_metadata.update(custom_lists_metadatum: nil)
          end
          format.html { redirect_to custom_fields_metadata, notice: 'CustomFieldsMetadatum was successfully updated.' }
          format.js
          format.json { respond_with_bip(custom_fields_metadata) }
        else
          format.html { render action: 'edit' }
          format.js { render json: custom_fields_metadata.errors, status: :unprocessable_entity }
          format.json { render json: custom_fields_metadata.errors, status: :unprocessable_entity }
        end
      end
    end
  end

  def destroy
    custom_fields_metadata = current_user.organization.custom_fields_metadatum.find(params[:id])
    custom_fields_metadata.destroy if custom_fields_metadata

    redirect_to :back  #reload page
  end

  private

  def custom_fields_metadatum_params
    params.require(:custom_fields_metadatum).permit(:name, :data_type, :update_permission_level, :custom_lists_metadata_id)
  end
end
