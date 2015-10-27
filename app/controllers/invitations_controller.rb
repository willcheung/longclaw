class InvitationsController < ApplicationController
	before_filter :authenticate_user!

	def new
		render :layout => "empty"
	end
end