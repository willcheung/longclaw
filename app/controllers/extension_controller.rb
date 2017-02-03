class ExtensionController < ApplicationController
  layout "extension", except: [:test]

  before_action :set_project, except: [:test, :index]

  def test
    render layout: "empty"
  end

  def index
  end

  def account
  end

  def alerts_tasks
  end

  def contacts
  end

  def metrics
  end

  private
  def set_project
    @project = Project.find '996c4ba3-56b4-44a5-9bdd-f21b5faae959'
  end
end
