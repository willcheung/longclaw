class InvitationsController < ApplicationController
	before_filter :authenticate_user!

	def new
		puts session["devise.google_data"]
		google_contacts_user = GoogleContactsApi::User.new(session["devise.google_data"])
		puts google_contacts_user.to_s + '!!!!!'
		@contacts = google_contacts_user.contacts

		render :layout => "empty"
	end
end