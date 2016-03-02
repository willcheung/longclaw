class SearchController < ApplicationController
	def results
  	@title = "Results"
		@activities = Activity.search_note("project").where("is_public = true and category='Note'")

  end
end