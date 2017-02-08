class CustomFieldsController < ApplicationController
  def update
    #Project.visible_to(current_user.organization_id, current_user.id)
    custom_field = CustomField.find(params[:id])
    if custom_field and custom_field.organization == current_user.organization  
      respond_to do |format|
        if custom_field.update(custom_field_params)
          format.html { redirect_to custom_field, notice: 'CustomField was successfully updated.' }
          format.js
          format.json { respond_with_bip(custom_field) }
        else
          format.html { render action: 'edit' }
          format.js { render json: custom_field.errors, status: :unprocessable_entity }
          format.json { render json: custom_field.errors, status: :unprocessable_entity }
        end
      end
    end
  end

  private

  def custom_field_params
    params.require(:custom_field).permit(:value)
  end
end
