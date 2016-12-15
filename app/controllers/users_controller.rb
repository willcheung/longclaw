class UsersController < ApplicationController
  before_filter :authenticate_user!
  before_action :set_user, only: [:show, :update, :destroy, :fill_in_info_update]

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

  # POST from onboarding#fill_in_form page
  def fill_in_info_update
    respond_to do |format|
      if @user.update(user_params)
        # If cluster hasn't been created yet, create it
        if @user.cluster_create_date.nil? and @user.mark_private == false
          # Kick off cluster analysis to backend
          ContextsmithService.get_emails_from_backend_with_callback(@user)
        else
          @user.update_attributes(cluster_create_date: Time.now)
        end

        format.html { redirect_to onboarding_tutorial_path }
      else
        format.html { render action: 'edit' }
      end
    end
  end

  private
  
  def set_user
    @user = User.find(params[:id])
  end

  # Never trust parameters from the scary internet, only allow the white list through.
  def user_params
    params.require(:user).permit(:title, :department, :mark_private, :role)
  end

end