class CustomListsController < ApplicationController
	def create
		custom_lists_metadatum = current_user.organization.custom_lists_metadatum.find(params[:custom_lists_metadatum_id])
		custom_lists_metadatum.custom_lists.create(option_value:"New option") if custom_lists_metadatum
		
		redirect_to :back  #reload page
	end

	def update
		#Project.visible_to(current_user.organization_id, current_user.id)
		custom_list_option = current_user.organization.custom_lists.find(params[:id])
		if custom_list_option
			respond_to do |format|
				if custom_list_option.update(custom_lists_params)
					format.html { redirect_to custom_list_option, notice: 'Custom list was successfully updated.' }
					format.js
					format.json { respond_with_bip(custom_list_option) }
				else
					format.html { render action: 'edit' }
					format.js { render json: custom_list_option.errors, status: :unprocessable_entity }
					format.json { render json: custom_list_option.errors, status: :unprocessable_entity }
				end
			end
		end
	end

	def destroy
		custom_list_option = current_user.organization.custom_lists.find(params[:id])
		custom_list_option.destroy if custom_list_option

		redirect_to :back #reload page
	end

	private

	def custom_lists_params
		params.require(:custom_list).permit(:option_value)
	end
end