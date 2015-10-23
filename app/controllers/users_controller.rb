class UsersController < ApplicationController
  before_filter :authenticate_user!

  def show
    @user = User.find(params[:id])
    unless @user == current_user
      redirect_to :back, :alert => "Access denied."
    end
  end

  def send_beta_teaser_email
  	@user = User.find_by_id(params[:user_id])

  	respond_to do |format|
  		if @user
  			UserMailer.beta_teaser_email(@user, params[:content]).deliver_later

  			format.html { redirect_to('http://www.contextsmith.com') }
  			format.json { render json: @user, status: 'User found, sending email.'}
  		else
  			format.html { redirect_to('http://www.contextsmith.com') }
  			format.json { render json: 'User not found.', status: 'User not found. No email sent.'}
  		end
  	end
  end

end