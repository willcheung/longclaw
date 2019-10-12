class UsersController < ApplicationController
  before_filter :authenticate_user!
  before_action :set_user, only: [:show, :update, :destroy, :fill_in_info_update]

  def show
    @user = User.find(params[:id])
    unless @user == current_user
      redirect_to :back, :alert => "Access denied."
    end
  end

  def me
    @user = current_user.slice(:first_name, :last_name, :email, :image_url, :time_zone, :title, :id)

    render json: @user
  end

  def destroy
    @user.destroy
    respond_to do |format|
      format.html { redirect_to settings_url }
    end
  end

  # Only used by settings#users for inviting users
  def create
    @user = User.new(user_params.merge(invited_by_id: current_user.id, role: current_user.role))
    respond_to do |format|
      if @user.save
        UserMailer.user_invitation_email(@user, get_full_name(current_user), new_user_registration_url(invited_by: current_user.first_name)).deliver_later

        format.html { redirect_to settings_users_path, notice: 'User was successfully invited.' }
        format.js  {render json: @user}
      else
        format.html { redirect_to settings_users_path, notice: @user.errors.full_messages.first }
        #format.json { render json: @account.errors, status: :unprocessable_entity }
        format.js { render json: @user.errors, status: :unprocessable_entity }
      end
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

  # POST from completing onboarding's fill_in_form
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
    params.require(:user).permit(:title, :first_name, :last_name, :organization_id, :email, :department, :mark_private, :role, :refresh_inbox, :is_disabled, :email_weekly_tracking, :email_onboarding_campaign, :email_new_features)
  end

end