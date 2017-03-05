class CustomFieldsController < ApplicationController
  def update
    custom_field = current_user.organization.custom_fields.find(params[:id])
    if custom_field
      respond_to do |format|
        if custom_field.update(custom_fields_params)
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

  def custom_fields_params
    params.require(:custom_field).permit(:value)
  end
end
