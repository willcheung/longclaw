class HomeController < ApplicationController
  layout 'empty', only: 'thank_you'

  def index
  	@title = "Welcome Will Cheung!"
  end

  def thank_you
  	@title = "Welcome to ContextSmith"
  end
end