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
    account = Account.find_by(id: contact_params[:account_id], organization_id: current_user.organization_id)
    if account.nil? or account.blank? 
      account = Account.find_by(name: contact_params[:account_id], organization_id: current_user.organization_id)
      if account.nil? or account.blank? # if account doesn't exist, create new one automatically
        account = Account.create(name: contact_params[:account_id], organization_id: current_user.organization_id)
      end
    end
    @contact = account.contacts.new(contact_params)
    respond_to do |format|
      if account.organization_id == current_user.organization_id && @contact.save
        format.html { redirect_to @contact, notice: 'Contact was successfully created.' }
        # format.json { render action: 'show', status: :created, location: @contact }
        format.js

        set_sfdc_client if @contact.account.is_linked_to_SFDC?

        if @sfdc_client
          export_result = @contact.export_cs_contact(@sfdc_client, @contact.account.salesforce_accounts.first.salesforce_account_id)
          puts "*** SFDC error: Error in ContactsController.create during creation of a contact in linked SFDC account. Detail: #{export_result[:detail]} ***" if export_result[:status] == "ERROR" # TODO: Warn the user that the contact in the linked SFDC account was not created.
        else
          puts "****SFDC**** Warning: no SFDC connection is available or can be established for user=#{current_user.email}, organization=#{current_user.organization.name}. Contact in linked Salesforce account was not created!"  # TODO: Warn the user that the contact in the linked SFDC account was not created.
        end
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

        if @sfdc_client
          export_result = @contact.export_cs_contact(@sfdc_client, @contact.account.salesforce_accounts.first.salesforce_account_id)
          puts "*** SFDC error: Error in ContactsController.update during update of contact in linked SFDC account. Detail: #{export_result[:detail]} ***" if export_result[:status] == "ERROR" # TODO: Warn the user that the contact in the linked SFDC account was not updated.
        end
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

        set_sfdc_client if @contact.account.is_linked_to_SFDC?

        puts "****SFDC**** Warning: no SFDC connection is available or can be established for user=#{current_user.email}, organization=#{current_user.organization.name}. Contact in linked Salesforce account was not updated!" if @sfdc_client.nil? # TODO: Issue a warning to the user that the linked SFDC opp was not updated!
      rescue ActiveRecord::RecordNotFound
        # redirect_to root_url, :flash => { :error => "Contact not found or is private." }
        redirect_to :back, :flash => { :error => "Contact not found or is private." }
      end
    end

    def set_sfdc_client
      sfdc_oauthuser = SalesforceController.get_sfdc_oauthuser(user: current_user) || SalesforceController.get_sfdc_oauthuser(organization: current_user.organization)  # Use current user's SFDC login/connection if available; otherwise, use admin's SFDC login/connection regardless of current user's role

      @sfdc_client = SalesforceService.connect_salesforce(sfdc_oauthuser: sfdc_oauthuser) if sfdc_oauthuser.present?
    end

    # Never trust parameters from the scary internet, only allow the white list through.
    def contact_params
      params.require(:contact).permit(:account_id, :first_name, :last_name, :email, :phone, :title, :department, :background_info, :external_source_id)
    end
end
