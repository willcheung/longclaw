class CustomFieldsMetadatumController < ApplicationController
  #Note: Probably should check if requestor has permission and visibility to view/edit a custom field.
  def create
    entity_type = CustomFieldsMetadatum.validate_and_return_entity_type(params[:entity_type])

    if (current_user.organization and entity_type)
      # Creating a metadata row will call the after_create callback and automatically create custom-field records for all existing entities
      CustomFieldsMetadatum.create(organization:current_user.organization, entity_type:entity_type, name:"New field", data_type:"Text", update_permission_level:User::ROLE[:Contributor])
    end

    redirect_to :back  #reload page
  end

  def update
    custom_fields_metadata = CustomFieldsMetadatum.find(params[:id])
    if custom_fields_metadata and custom_fields_metadata.organization == current_user.organization  
      respond_to do |format|
        if custom_fields_metadata.update(custom_fields_metadatum_params)
          format.html { redirect_to custom_fields_metadata, notice: 'CustomField was successfully updated.' }
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
    print "----> Deleting a custom field metadata rec id=", params[:id], "!\n"
    custom_fields_metadata = CustomFieldsMetadatum.find(params[:id])
    custom_fields_metadata.destroy if custom_fields_metadata and custom_fields_metadata.organization == current_user.organization  

    redirect_to :back  #reload page
  end

  private

  def custom_fields_metadatum_params
    params.require(:custom_fields_metadatum).permit(:name, :data_type, :update_permission_level)
  end
end
