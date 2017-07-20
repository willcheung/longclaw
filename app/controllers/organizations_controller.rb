class OrganizationsController < ApplicationController
  before_action :check_if_admin
  before_action :set_organization, only: [:show, :edit, :update, :destroy]

  layout 'empty', only: 'new'

  # GET /organizations
  # GET /organizations.json
  def index
    @organizations = Organization.includes(:projects, :accounts).all
  end

  # GET /organizations/1
  # GET /organizations/1.json
  def show
  end

  # GET /organizations/new
  def new
    @organization = Organization.new(domain: get_domain(current_user.email),
                                     name: get_short_name(get_domain(current_user.email)).capitalize,
                                     is_active: true,
                                     owner_id: current_user.id
                                    )
  end

  # GET /organizations/1/edit
  def edit
  end

  # POST /organizations
  # POST /organizations.json
  def create
    @organization = Organization.new(organization_params)

    respond_to do |format|
      if @organization.save
        format.html { redirect_to @organization, notice: 'organization was successfully created.' }
        format.json { render action: 'show', status: :created, location: @organization }
      else
        format.html { render action: 'new' }
        format.json { render json: @organization.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /organizations/1
  # PATCH/PUT /organizations/1.json
  def update
    respond_to do |format|
      if @organization.update(organization_params)
        format.html { redirect_to @organization, notice: 'organization was successfully updated.' }
        format.json { head :no_content }
      else
        format.html { render action: 'edit' }
        format.json { render json: @organization.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /organizations/1
  # DELETE /organizations/1.json
  def destroy
    @organization.destroy
    respond_to do |format|
      format.html { redirect_to settings_super_user_url }
      format.json { head :no_content }
    end
  end

  private
    def check_if_admin
      @super_admin = %w(wcheung@contextsmith.com syong@contextsmith.com vluong@contextsmith.com klu@contextsmith.com beders@contextsmith.com)
      redirect_to root_path and return unless @super_admin.include?(current_user.email)
    end

    # Use callbacks to share common setup or constraints between actions.
    def set_organization
      @organization = Organization.find(params[:id])
    end

    # Never trust parameters from the scary internet, only allow the white list through.
    def organization_params
      params.require(:organization).permit(:name, :domain, :is_active)
    end
end
