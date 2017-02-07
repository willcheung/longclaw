class CustomFieldsController < ApplicationController
  def create
    puts "creating a new custom field"
  end

  def update
    puts "updating a custom field"
    #Project.visible_to(current_user.organization_id, current_user.id)
    @custom_field = CustomField.find(params[:id])
    if @custom_field
      print "name=", @custom_field.custom_fields_metadatum.name, "\n"
      
      respond_to do |format|
        if @custom_field.update(custom_field_params)
          format.html { redirect_to @custom_field, notice: 'CustomField was successfully updated.' }
          format.js
          format.json { respond_with_bip(@custom_field) }
        else
          format.html { render action: 'edit' }
          format.js { render json: @custom_field.errors, status: :unprocessable_entity }
          format.json { render json: @custom_field.errors, status: :unprocessable_entity }
        end
      end
    end
  end

  def destroy
    puts "deleting a custom field"
  end

  private

  def custom_field_params
    params.require(:custom_field).permit(:customizable, :value)
  end
end
