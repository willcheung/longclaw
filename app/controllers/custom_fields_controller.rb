class CustomFieldsController < ApplicationController
  def update
    #Project.visible_to(current_user.organization_id, current_user.id)
    _custom_field = CustomField.find(params[:id])
    if _custom_field and _custom_field.organization == current_user.organization  
      respond_to do |format|
        if _custom_field.update(custom_field_params)
          format.html { redirect_to _custom_field, notice: 'CustomField was successfully updated.' }
          format.js
          format.json { respond_with_bip(_custom_field) }
        else
          format.html { render action: 'edit' }
          format.js { render json: _custom_field.errors, status: :unprocessable_entity }
          format.json { render json: _custom_field.errors, status: :unprocessable_entity }
        end
      end
    end
  end

  private

  def custom_field_params
    params.require(:custom_field).permit(:customizable, :value)
  end
end
