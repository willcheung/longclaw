class UsersController < ApplicationController
  before_filter :authenticate_user!
  before_action :set_user, only: [:show, :update, :destroy]

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

  def update
    respond_to do |format|
      if @user.update(user_params)
        format.html { redirect_to @user, notice: 'User was successfully updated.' }
        format.json { respond_with_bip(@user) }
        format.js { render action: 'show', status: :created, location: @user }
      else
        format.html { render action: 'edit' }
        format.json { respond_with_bip(@user) }
        format.js { render json: @user.errors, status: :unprocessable_entity }
      end
    end
  end

  private
  
  def set_user
    @user = User.find(params[:id])
  end

  # Never trust parameters from the scary internet, only allow the white list through.
  def user_params
    params.require(:user).permit(:title, :department)
  end

end