class SearchController < ApplicationController
	def results
  	@title = "Results"
		@activities = Activity.search_by_message("project").where("is_public = true")

  end
end