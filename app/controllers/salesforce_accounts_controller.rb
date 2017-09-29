class SalesforceAccountsController < ApplicationController

  def set_visible_salesforce_account
  #   @salesforce_account = Project.visible_to(current_user.organization_id, current_user.id).find(params[:id])
  # rescue ActiveRecord::RecordNotFound
  #   redirect_to root_url, :flash => { :error => "Project not found or is private." }
  end

  def index
  end

  def update
  end

  def delete
  end
end
