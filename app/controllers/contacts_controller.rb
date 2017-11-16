class ContactsController < ApplicationController
  before_action :set_contact, only: [:show, :edit, :update, :destroy]

  # GET /contacts
  # GET /contacts.json
  def index
    @contacts = Contact.includes(:projects).includes(:account).all
  end

  # GET /contacts/1
  # GET /contacts/1.json
  def show
  end

  # GET /contacts/new
  def new
    @contact = Contact.new
  end

  # GET /contacts/1/edit
  def edit
  end

  # POST /contacts
  # POST /contacts.json
  def create
    @contact = Contact.new(contact_params)
    account = Account.find(@contact.account_id)  # didn't verify account_id!
    respond_to do |format|
      if account.organization_id == current_user.organization_id && @contact.save
        format.html { redirect_to @contact, notice: 'Contact was successfully created.' }
        # format.json { render action: 'show', status: :created, location: @contact }
        format.js 
      else
        format.html { render action: 'new' }
        format.js { render json: @contact.errors, status: :unprocessable_entity }
        # format.json { render json: @contact.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /contacts/1
  # PATCH/PUT /contacts/1.json
  def update
    respond_to do |format|
      #if Contact.where(id: @contact.id).update_all(contact_params)  #allows updating Contact if e-mail is null
      if @contact.update(contact_params)
        # format.html { redirect_to @contact, notice: 'Contact was successfully updated.' }
        format.html { redirect_to :back, notice: 'Contact was successfully updated.' }
        format.json { respond_with_bip(@contact) }
        format.js
      else
        format.html { render action: 'edit' }
        format.json { respond_with_bip(@contact) }
        format.js { render json: @contact.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /contacts/1
  # DELETE /contacts/1.json
  def destroy
    @contact.destroy
    respond_to do |format|
      format.html { redirect_to :back }
      # format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_contact
      begin
        @contact = Contact.visible_to(current_user).find(params[:id])
      rescue ActiveRecord::RecordNotFound
        # redirect_to root_url, :flash => { :error => "Contact not found or is private." }
        redirect_to :back, :flash => { :error => "Contact not found or is private." }
      end
    end

    # Never trust parameters from the scary internet, only allow the white list through.
    def contact_params
      params.require(:contact).permit(:account_id, :first_name, :last_name, :email, :phone, :title, :department, :background_info, :external_source_id)
    end
end
