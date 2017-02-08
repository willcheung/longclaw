class CustomFieldsMetadatumController < ApplicationController
  #Note: Probably should check if requestor has permission and visibility to view/edit a custom field.
  def create
    _entity_type = CustomFieldsMetadatum.validate_and_return_entity_type(params[:entity_type])

    if (current_user.organization and _entity_type)
      # Creating a metadata row will call the after_create callback and automatically create custom-field records for all existing entities
      CustomFieldsMetadatum.create(organization:current_user.organization, entity_type:_entity_type, name:"New field", data_type:"Text", update_permission_level:User::ROLE[:Contributor])
    end

    redirect_to :back  #reload page
  end

  def update
    _custom_fields_metadata = CustomFieldsMetadatum.find(params[:id])
    if _custom_fields_metadata and _custom_fields_metadata.organization == current_user.organization  
      respond_to do |format|
        if _custom_fields_metadata.update(custom_fields_metadatum_params)
          format.html { redirect_to _custom_fields_metadata, notice: 'CustomField was successfully updated.' }
          format.js
          format.json { respond_with_bip(_custom_fields_metadata) }
        else
          format.html { render action: 'edit' }
          format.js { render json: _custom_fields_metadata.errors, status: :unprocessable_entity }
          format.json { render json: _custom_fields_metadata.errors, status: :unprocessable_entity }
        end
      end
    end
  end

  def destroy
    print "----> Deleting a custom field metadata rec id=", params[:id], "!\n"
    _custom_fields_metadata = CustomFieldsMetadatum.find(params[:id])
    _custom_fields_metadata.destroy if _custom_fields_metadata and _custom_fields_metadata.organization == current_user.organization  

    redirect_to :back  #reload page
  end

  private

  def custom_fields_metadatum_params
    params.require(:custom_fields_metadatum).permit(:id, :entity_type, :name, :data_type, :update_permission_level)
  end
end
