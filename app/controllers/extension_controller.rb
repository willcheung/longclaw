class ExtensionController < ApplicationController

  def test
    render layout: "empty"
  end

  def time_spent
    @project = Project.find '996c4ba3-56b4-44a5-9bdd-f21b5faae959'
    render layout: "plugin"
  end
end
