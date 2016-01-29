class HomeController < ApplicationController
  layout 'empty', only: 'access_denied'

  def index
    
  end

  def access_denied
    # Nothing here
  end
end