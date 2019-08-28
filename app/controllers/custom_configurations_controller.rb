class CustomConfigurationsController < ApplicationController
  before_action :set_custom_configuration, only: [:update, :destroy]

  #def create
  #end

  def update
    respond_to do |format|
      if @custom_configuration.update(custom_configurations_params)
        #format.html { redirect_to :back, notice: 'Custom Configuration was successfully saved.' }
        format.json { respond_with_bip(@custom_configuration) }
      else
        #format.html { render action: 'edit' }
        format.json { respond_with_bip(@custom_configuration) }
      end
    end
  end

  def destroy
    @custom_configuration.destroy
    respond_to do |format|
      format.html { redirect_to :back }
      # format.json { head :no_content }
    end
  end

  private

  def set_custom_configuration 
    begin
      if custom_configurations_params[:user_id]
        if custom_configurations_params[:user_id] == current_user.id  #only allow user to edit his/her own configuration
          @custom_configuration = CustomConfiguration.where(organization: current_user.organization, user_id: custom_configurations_params[:user_id]).find(params[:id])
        else # Unauthorized user!
          raise ActiveRecord::RecordNotFound
        end
      else # No user_id passed
        @custom_configuration = CustomConfiguration.where(organization: current_user.organization).find(params[:id])
      end
    rescue ActiveRecord::RecordNotFound
      redirect_to root_path, :flash => { :error => "Custom Configuration not found or is private." }
    end
  end

  def custom_configurations_params
    params.require(:custom_configuration).permit(:id, :user_id, :config_type, :config_value)  # :organization_id
  end
end
