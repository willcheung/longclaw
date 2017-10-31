class InitialSalesforceLoginsJob < ActiveJob::Base
  queue_as :default

  # Automatic actions to perform when user establishes a SFDC connection.
  #  e.g., 
  #    - Create a default mapping between CS and SFDC fields, if none exists for current user's org
  #    - Runs actions in SalesforceController.import_and_create_contextsmith() for current_user (see doc of method for details)
  def perform(current_user)
    ActiveRecord::Base.connection_pool.with_connection do
      puts "\n-> InitialSalesforceLoginsJob: The following user has signed into SFDC: '#{get_full_name(current_user)}' (email='#{current_user.email}'), organization='#{current_user.organization.name}' (#{current_user.organization_id}), role='#{current_user.role}'...\n"

      sfdc_client = SalesforceService.connect_salesforce(user: current_user)

      if sfdc_client.present?
        # Create a default mapping between CS and SFDC fields if none exist (Note: Any user, including non-admins, may trigger this)
        current_org_entity_fields_metadatum = current_user.organization.entity_fields_metadatum
        EntityFieldsMetadatum.create_default_for(current_user.organization) if current_org_entity_fields_metadatum.first.blank? 
        EntityFieldsMetadatum.set_default_sfdc_fields_mapping_for(sfdc_client, current_user.organization) if current_org_entity_fields_metadatum.none?{ |efm| efm.salesforce_field.present? }
        
        SalesforceOpportunity.refresh_picklists(client: sfdc_client, organization: current_user.organization, force_refresh: false)  # create initial forecast category and stage picklists; don't refresh if values exist
        SalesforceController.import_and_create_contextsmith(client: sfdc_client, user: current_user) # Load SFDC Accounts and new SFDC Opportunities, update mapped fields, and sync contacts
      else
        puts "****SFDC**** Salesforce error during InitialSalesforceLoginsJob: Cannot establish a Salesforce connection! user_id='#{current_user.id}' of organization_id=#{current_user.organization_id}"
      end
    end

    puts "\n-> InitialSalesforceLoginsJob: Completed successfully.\n"
  rescue => e
    puts "ERROR (InitialSalesforceLoginsJob): Something went wrong: " + e.message
    puts e.backtrace.join("\n")
  end

end
