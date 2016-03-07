class UsersController < ApplicationController
  before_filter :authenticate_user!
  before_action :set_user, only: [:show, :destroy]

  def show
    @user = User.find(params[:id])
    unless @user == current_user
      redirect_to :back, :alert => "Access denied."
    end
  end

  def destroy
    @user.destroy
    respond_to do |format|
      format.html { redirect_to settings_url }
    end
  end

  private
  
  def set_user
    @user = User.find(params[:id])
  end

end