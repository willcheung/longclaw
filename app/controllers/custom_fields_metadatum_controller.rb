class CustomFieldsMetadatumController < ApplicationController
  before_action :get_current_user_org, only: ['create']

  #Note: do we need to check if requestor has permission to edit?
  def create
    @entity_type = CustomFieldsMetadatum.validateAndReturnValidEntityType(params[:entity_type])

    if (@current_user_org and @entity_type)
      print "Creating a new custom field metadata rec of type ", @entity_type.to_s, "\n"
      # Creating a metadata row will call the after_create callback and automatically create custom-field records for all existing entities
      CustomFieldsMetadatum.create(organization:@current_user_org, entity_type:@entity_type, name:"New field", data_type:"Text", update_permission_level:User::ROLE[:Contributor])
    end

    redirect_to :back  #reload page
  end

  def update
    #print "Updating a custom field metadata record", params[:id], "!\n"
    #Project.visible_to(current_user.organization_id, current_user.id)
    @custom_fields_metadata = CustomFieldsMetadatum.find(params[:id])
    if @custom_fields_metadata
      respond_to do |format|
        if @custom_fields_metadata.update(custom_fields_metadatum_params)
          format.html { redirect_to @custom_fields_metadata, notice: 'CustomField was successfully updated.' }
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
    print "----> Deleting a custom field metadata rec id=", params[:id], "!\n"
    @custom_fields_metadata = CustomFieldsMetadatum.find(params[:id])
    @custom_fields_metadata.destroy if @custom_fields_metadata  # children destroyed automatically

    redirect_to :back  #reload page
  end

  private

  def get_current_user_org
    @current_user_org = current_user.organization
  end

  def custom_fields_metadatum_params
    params.require(:custom_fields_metadatum).permit(:id, :entity_type, :name, :data_type, :update_permission_level)
  end
end
