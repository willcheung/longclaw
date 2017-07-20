class EntityFieldsMetadataController < ApplicationController
  before_action :set_entity_fields_metadatum, only: [:update, :destroy]

  def create
    current_user.organization.entity_fields_metadatum.create(name:"New list")
    
    redirect_to :back  #reload page
  end

  def update
    if @entity_fields_metadatum  
      respond_to do |format|
        if @entity_fields_metadatum.update(entity_fields_metadatum_params)
          format.html { redirect_to @entity_fields_metadatum, notice: 'EntityFieldsMetadatum was successfully updated.' }
          format.js
          format.json { respond_with_bip(@entity_fields_metadatum) }
        else
          format.html { render action: 'edit' }
          format.js { render json: @entity_fields_metadatum.errors, status: :unprocessable_entity }
          format.json { render json: @entity_fields_metadatum.errors, status: :unprocessable_entity }
        end
      end
    end
  end

  def destroy
    @entity_fields_metadatum.destroy if @entity_fields_metadatum

    redirect_to :back  #reload page
  end

  private

  def set_entity_fields_metadatum
    @entity_fields_metadatum = current_user.organization.entity_fields_metadatum.find(params[:id])
  end

  def entity_fields_metadatum_params
    params.require(:entity_fields_metadatum).permit(:name, :default_value, :salesforce_field, :read_permission_role, :update_permission_role)
  end
end
