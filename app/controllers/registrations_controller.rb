class RegistrationsController < Devise::RegistrationsController
  prepend_before_filter :require_no_authentication, only: [:new, :cancel]
  prepend_before_filter :allow_params_authentication!, only: :create
  before_filter :authenticate_scope!, only: :create

  def new
    puts 'Our RegistrationsController#new', '====================='
    super
  end
  
  def destroy
    puts 'Our RegistrationsController#destroy', '====================='
    super
  end
  
  def create
    puts 'Our RegistrationsController#create', '====================='
    # allow_params_authentication!
    super do |resource|
      resource = resource_class.update_for_oathkeeper_auth(resource, sign_up_params, (cookies[:timezone] || 'UTC'))
      p resource
      p resource.persisted?
      p resource.active_for_authentication?
    end
    # @user = resource_class.new_with_session(sign_up_params || {}, session)
    # resource = warden.authenticate!(auth_options)
    # @user = resource_class.update_for_oathkeeper_auth(resource, sign_up_params, (cookies[:timezone] || 'UTC'))

    # if @user.persisted?
    #   puts "Exchange login success for user " + @user.email
    #   flash[:notice] = "Welcome, #{resource.first_name}!"
    #   sign_in(@user)
    #   respond_with @user, location: after_sign_in_path_for(@user)
    # else
    #   reset_session
    #   clean_up_passwords @user
    #   set_minimum_password_length
    #   puts "Can't persist user!"
    #   ahoy.track("Error logging in", message: "Can't persist user!")
    #   redirect_to new_user_registration_path
    # end
  end

end