class CustomListsMetadataController < ApplicationController
	def create
		current_user.organization.custom_lists_metadatum.create(name:"New list")
		
		redirect_to :back  #reload page
	end

	def update
		custom_lists_metadata = current_user.organization.custom_lists_metadatum.find(params[:id])
		if custom_lists_metadata  
			respond_to do |format|
				if custom_lists_metadata.update(custom_lists_metadatum_params)
					format.html { redirect_to custom_lists_metadata, notice: 'CustomListsMetadatum was successfully updated.' }
					format.js
					format.json { respond_with_bip(custom_lists_metadata) }
				else
					format.html { render action: 'edit' }
					format.js { render json: custom_lists_metadata.errors, status: :unprocessable_entity }
					format.json { render json: custom_lists_metadata.errors, status: :unprocessable_entity }
				end
			end
		end
	end

	def destroy
		custom_lists_metadata = current_user.organization.custom_lists_metadatum.find(params[:id])
		custom_lists_metadata.destroy if custom_lists_metadata

		redirect_to :back  #reload page
	end

	private

	def custom_lists_metadatum_params
		params.require(:custom_lists_metadatum).permit(:name)
	end
end
