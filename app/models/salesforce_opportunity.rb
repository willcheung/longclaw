# == Schema Information
#
# Table name: salesforce_opportunities
#
#  id                        :integer          not null, primary key
#  salesforce_opportunity_id :string           default(""), not null
#  salesforce_account_id     :string           default(""), not null
#  name                      :string           default(""), not null
#  description               :text
#  is_closed                 :boolean
#  is_won                    :boolean
#  stage_name                :string
#  close_date                :date
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  contextsmith_project_id   :uuid
#  probability               :decimal(5, 2)
#  expected_revenue          :decimal(14, 2)
#  amount                    :decimal(14, 2)
#  forecast_category_name    :string
#  owner_id                  :string
#
# Indexes
#
#  index_salesforce_opportunities_on_salesforce_opportunity_id  (salesforce_opportunity_id) UNIQUE
#

class SalesforceOpportunity < ActiveRecord::Base
	belongs_to	:salesforce_account, foreign_key: "salesforce_account_id", primary_key: "salesforce_account_id"
  belongs_to  :project, foreign_key: "contextsmith_project_id"

  scope :is_open, -> {where(is_closed: false)}
  scope :is_linked, -> {where.not(contextsmith_project_id: nil)}
  scope :is_not_linked, -> {where(contextsmith_project_id: nil)}

  validates :name, :close_date, presence: true

  # This class method finds SFDC opportunities and creates a local model out of all opportunities associated with each SFDC-linked CS account.
  # For Admin users, speicfy organization, this will get all SFDC opportunities belonging to linked CS/SFDC accounts, and is Open or was Closed within the last year.  For all other users, this will get all SFDC opportunities belonging to the current_user's SFDC User, and is Open or was Closed within the last year.
  # Params:    client - a valid SFDC connection
  #            user - (required, if individual SFDC user) the user of the organization into which to upsert the SFDC accounts
  #            organization - (required, if admin SFDC user) the organization into which to upsert the SFDC accounts
  #            query_range - (optional) the limit for SFDC query results
  # Returns:   A hash that represents the execution status/result. Consists of:
  #             status - string "SUCCESS" if load successful; otherwise, "ERROR".
  #             result - if successful, contains the # of opportunities added/updated; if an error occurred, contains the title of the error.
  #             detail - contains the details of an error.
  # TODO: This recovers if an error occurs while running a SFDC query during the process, but need to add code to save error messages.
  def self.load_opportunities(client: , user: nil , organization: nil, query_range: 500)
    val = []

    total_opportunities = 0
    error_occurred = false
    if organization.present?
      sfdc_accounts = SalesforceAccount.where(contextsmith_organization_id: organization.id).is_linked

      sfdc_accounts.each do |a|
        query_statement = "SELECT Id, AccountId, OwnerId, Name, Amount, Description, IsWon, IsClosed, StageName, CloseDate, Probability, ForecastCategoryName from Opportunity where AccountId = '#{a.salesforce_account_id}' AND ((IsClosed = FALSE) OR (IsClosed = TRUE and CloseDate > #{(Time.now - 1.year).utc.strftime('%Y-%m-%d')})) LIMIT #{query_range}"

        query_result = SalesforceService.query_salesforce(client, query_statement)
        # puts "query_statement: #{ query_statement }" 
        # puts "query_result: #{ query_result }"
        # puts "query_result result length => #{query_result[:result].length}"
        
        if query_result[:status] == "ERROR"
          puts "** SalesforceService error: During loading SFDC opportunities, a query to Salesforce using SalesforceService.query_salesforce in SalesforceOpportunity.load_opportunities had errors!  #{ query_result[:result] } Detail: #{ query_result[:detail] }"
          error_occurred = true
        else
          query_result[:result].each do |opp|
            val << "('#{opp.Id}', 
                    '#{opp.OwnerId}', 
                    '#{opp.AccountId}', 
                    #{SalesforceOpportunity.sanitize(opp.Name)}, 
                    #{SalesforceOpportunity.sanitize(opp.Description)}, 
                    #{opp.Amount.nil? ? "0.00" : opp.Amount}, 
                    #{opp.IsClosed}, 
                    #{opp.IsWon}, 
                    #{SalesforceOpportunity.sanitize(opp.StageName)},
                    '#{opp.CloseDate}',
                    #{SalesforceOpportunity.sanitize(opp.Probability)},
                    #{SalesforceOpportunity.sanitize(opp.ForecastCategoryName)},
                    '#{Time.now}', '#{Time.now}')"
          end
        end

        insert = 'INSERT INTO "salesforce_opportunities" ("salesforce_opportunity_id", "owner_id", "salesforce_account_id", "name", "description", "amount", "is_closed", "is_won", "stage_name", "close_date", "probability", "forecast_category_name", "created_at", "updated_at") VALUES'
        on_conflict = 'ON CONFLICT (salesforce_opportunity_id) DO UPDATE SET owner_id = EXCLUDED.owner_id, salesforce_account_id = EXCLUDED.salesforce_account_id, name = EXCLUDED.name, description = EXCLUDED.description, amount = EXCLUDED.amount, is_closed = EXCLUDED.is_closed, is_won = EXCLUDED.is_won, stage_name = EXCLUDED.stage_name, close_date = EXCLUDED.close_date, probability = EXCLUDED.probability, forecast_category_name = EXCLUDED.forecast_category_name, updated_at = EXCLUDED.updated_at'
        values = val.join(', ')

        if val.present?
          SalesforceOpportunity.transaction do
            SalesforceOpportunity.connection.execute([insert,values,on_conflict].join(' '))
          end

          total_opportunities += query_result[:result].length
          val = []
        end
      end  # End: sfdc_accounts.each do |a|
    elsif user.present?  # single SFDC user
      sfdc_userid = SalesforceService.get_salesforce_user_uuid(user.organization_id, user.id)
      query_statements = []
      query_statements << "SELECT Id, AccountId, OwnerId, Name, Amount, Description, IsWon, IsClosed, StageName, CloseDate, Probability, ForecastCategoryName from Opportunity where OwnerId = '#{sfdc_userid}' AND ((IsClosed = FALSE) OR (IsClosed = TRUE and CloseDate > #{(Time.now - 1.year).utc.strftime('%Y-%m-%d')})) LIMIT #{query_range}"  # "Closed within the last year & all Open Opps"
      # query_statements << "SELECT Id, AccountId, OwnerId, Name, Amount, Description, IsWon, IsClosed, StageName, CloseDate, Probability, ForecastCategoryName from Opportunity where OwnerId = '#{sfdc_userid}' AND IsClosed = FALSE ORDER BY CloseDate DESC LIMIT 10" # "recent 10 Open Opps"

      query_statements.each do |query_statement|
        query_result = SalesforceService.query_salesforce(client, query_statement)
        
        if query_result[:status] == "ERROR"
          puts "** SalesforceService error: During loading SFDC opportunities, query_salesforce() in SalesforceOpportunity.load_opportunities had errors!  #{ query_result[:result] } Detail: #{ query_result[:detail] }"
          error_occurred = true
        else
          query_result[:result].each do |opp|
            val << "('#{opp.Id}', 
                    '#{opp.OwnerId}', 
                    '#{opp.AccountId}', 
                    #{SalesforceOpportunity.sanitize(opp.Name)}, 
                    #{SalesforceOpportunity.sanitize(opp.Description)}, 
                    #{opp.Amount.nil? ? "0.00" : opp.Amount}, 
                    #{opp.IsClosed}, 
                    #{opp.IsWon}, 
                    #{SalesforceOpportunity.sanitize(opp.StageName)},
                    '#{opp.CloseDate}',
                    #{SalesforceOpportunity.sanitize(opp.Probability)},
                    #{SalesforceOpportunity.sanitize(opp.ForecastCategoryName)},
                    '#{Time.now}', '#{Time.now}')"
          end
          total_opportunities += query_result[:result].length
        end
      end # End: query_statements.each do |query_statement|

      insert = 'INSERT INTO "salesforce_opportunities" ("salesforce_opportunity_id", "owner_id", "salesforce_account_id", "name", "description", "amount", "is_closed", "is_won", "stage_name", "close_date", "probability", "forecast_category_name", "created_at", "updated_at") VALUES'
      on_conflict = 'ON CONFLICT (salesforce_opportunity_id) DO UPDATE SET owner_id = EXCLUDED.owner_id, salesforce_account_id = EXCLUDED.salesforce_account_id, name = EXCLUDED.name, description = EXCLUDED.description, amount = EXCLUDED.amount, is_closed = EXCLUDED.is_closed, is_won = EXCLUDED.is_won, stage_name = EXCLUDED.stage_name, close_date = EXCLUDED.close_date, probability = EXCLUDED.probability, forecast_category_name = EXCLUDED.forecast_category_name, updated_at = EXCLUDED.updated_at'
      values = val.join(', ')

      if val.present?
        SalesforceOpportunity.transaction do
          SalesforceOpportunity.connection.execute([insert,values,on_conflict].join(' '))
        end

        val = []
      end
    end

    if user.blank? && organization.blank?
      return { status: "ERROR", result: "SalesforceOpportunity.load_opportunities", detail: "Neither user nor organization was specified in call to method." }
    elsif error_occurred
      return { status: "ERROR", result: "", detail: "" } # TODO: capture error messages above
    elsif total_opportunities > 0
      return { status: "SUCCESS", result: "#{total_opportunities} opportunities added/updated." }
    else
      return { status: "SUCCESS", result: "Warning: no opportunities added." }
    end
	end

  # For salesforce_opportunity, updates the local copy and pushes change to Salesforce
  def self.update_all_salesforce(client: , salesforce_opportunity: , fields: , current_user: )
    # return { status: "ERROR", result: "Simulated SFDC error", detail: "Simulated detail" }
    return { status: "ERROR", result: "ContextSmith Error", detail: "Parameter passed to an internal function is invalid." } if client.nil?
    return { status: "ERROR", result: "Salesforce opportunity update error", detail: "Salesforce opportunity does not exist or this user does not exist." } if salesforce_opportunity.blank? || current_user.blank?

    if salesforce_opportunity.salesforce_account.organization == current_user.organization
      # puts "\n\nUpdating #{salesforce_opportunity.name}.... "

      begin
        fields[:close_date].strip!
        close_date = fields[:close_date].blank? ? nil : Date.strptime(fields[:close_date], "%m-%d-%Y")
      rescue ArgumentError => e
        begin
          close_date = Date.strptime(fields[:close_date], "%m/%d/%Y")
        rescue ArgumentError => e
          return { status: "ERROR", result: "Salesforce opportunity update error", detail: e.to_s + ". Cannot parse close_date '#{fields[:close_date]}'" }
        end
      end

      #TODO: Make update of CS and SFDC a single Unit of work (2 phase commit?)
      # Update Contextsmith model
      begin
        salesforce_opportunity.update(name: fields[:name], stage_name: fields[:stage_name], close_date: close_date, probability: fields[:probability], amount: fields[:amount], forecast_category_name: fields[:forecast_category_name]) # omitted: expected_revenue: fields[:expected_revenue]
      rescue => e
        return { status: "ERROR", result: "Salesforce opportunity update error", detail: e.to_s }
      end

      # Update Salesforce
      # Put the fields and values to be updated into a hash object.
      sObject_meta = { id: salesforce_opportunity.salesforce_opportunity_id, type: "Opportunity" }
      sObject_fields = { name: fields[:name], stage_name: fields[:stage_name], close_date: close_date, probability: fields[:probability], amount: fields[:amount], forecast_category_name: fields[:forecast_category_name] }
      update_result = SalesforceService.update_salesforce(client: client, update_type: "opportunity", sObject_meta: sObject_meta, sObject_fields: sObject_fields)

      if update_result[:status] == "SUCCESS"
        puts "-> SFDC opportunity was updated from a ContextSmith salesforce_opportunity. SFDC Opportunity Id='#{ salesforce_opportunity.salesforce_opportunity_id }'."
      else  # Salesforce update failure
        puts "****SFDC****: Salesforce error in SalesforceOpportunity.update_all_salesforce().  #{update_result[:result]}  Details: #{ update_result[:detail] }."
        return { status: "ERROR", result: update_result[:result], detail: update_result[:detail] + " sObject_fields=#{ sObject_fields }" } 
      end
    else # End: if salesforce_opportunity.salesforce_account.organization == current_user.organization
      return { status: "ERROR", result: "Salesforce opportunity update error", detail: "Salesforce opportunity does not exist or this user does not have access to it." } 
    end

    return { status: "SUCCESS", result: "Update completed." }
  end

  # Native and custom CS fields are updated according to the explicit mapping of a field of a SFDC opportunity to a field of a CS opportunity. This is for all active and confirmed opportunities visible to current_user. Process aborts immediately if there is an update/SFDC error.
  def self.refresh_fields(current_user)
    # opportunities = Project.visible_to_admin(current_user.organization_id).is_active.is_confirmed.joins(:salesforce_opportunity).where("salesforce_opportunities.contextsmith_project_id IS NOT NULL")
    opportunities = Project.visible_to(current_user.organization_id, current_user.id).is_active.is_confirmed.joins(:salesforce_opportunity).where("salesforce_opportunities.contextsmith_project_id IS NOT NULL")
    opportunity_standard_fields = EntityFieldsMetadatum.get_sfdc_fields_mapping_for(organization_id: current_user.organization_id, entity_type: EntityFieldsMetadatum::ENTITY_TYPE[:Project])
    opportunity_custom_fields = CustomFieldsMetadatum.where("organization_id = ? AND entity_type = ? AND salesforce_field is not null", current_user.organization_id, CustomFieldsMetadatum.validate_and_return_entity_type(CustomFieldsMetadatum::ENTITY_TYPE[:Project], true))
    # puts "Any opps mapped?=#{opportunities.find{|p| p.salesforce_opportunity.present?}.blank?}"
    # puts "\n\nopportunity_standard_fields: #{opportunity_standard_fields}\nopportunity_custom_fields: #{opportunity_custom_fields}\n"

    unless opportunities.first.blank? || (opportunity_standard_fields.blank? && opportunity_custom_fields.blank?) # nothing to do if no active+confirmed opportunities or no opportunity field mappings are found
      @client = SalesforceService.connect_salesforce(current_user.organization_id)
      #@client=nil # simulates a Salesforce connection error

      unless @client.nil?  # unless SFDC connection error
        # standard fields
        update_result = Project.update_fields_from_sfdc(client: @client, opportunities: opportunities, sfdc_fields_mapping: opportunity_standard_fields)
        if update_result[:status] == "ERROR"
          detail = {}
          detail[:failure_method_location] = "Project.update_fields_from_sfdc()"
          detail[:error_detail] = "Error while attempting to load standard fields from Salesforce Opportunities.  #{ update_result[:result] } Details: #{ update_result[:detail] }"
          return { status: "ERROR", result: "Update error", detail: detail }
        end

        # custom fields
        opportunities.each do |s|
          unless s.salesforce_opportunity.nil?
            # puts "**** SFDC opportunity:\"#{s.salesforce_opportunity.name}\" --> CS opportunity:\"#{s.name}\" ****\n"
            load_result = Project.load_salesforce_fields(client: @client, project_id: s.id, sfdc_opportunity_id: s.salesforce_opportunity.salesforce_opportunity_id, opportunity_custom_fields: opportunity_custom_fields)

            if load_result[:status] == "ERROR"
              detail = {}
              detail[:failure_method_location] = "Project.load_salesforce_fields()"
              detail[:error_detail] = "Error while attempting to load fields from Salesforce Opportunity \"#{s.salesforce_opportunity.name}\" (sfdc_id='#{s.salesforce_opportunity.salesforce_opportunity_id}') to CS Opportunity \"#{s.name}\" (opportunity_id='#{s.id}').  #{ load_result[:result] } Details: #{ load_result[:detail] }"
              return { status: "ERROR", result: "Update error", detail: detail }
            end
          end
        end # End: opportunities.each do |s|
      else
        puts "****SFDC****: Salesforce error in SalesforceOpportunity.refresh_fields: Cannot establish a connection!"
        return { status: "ERROR", result: SalesforceController::ERRORS[:SalesforceConnectionError], detail: "Unable to connect to Salesforce." }
      end
    else # no active+confirmed opportunities and no opportunity field mappings found
      return { status: "SUCCESS", result: "Warning: no opportunities updated." }
    end

    return { status: "SUCCESS", result: "Refresh completed." }
  end

  # Create/refresh local custom lists copies of the available SFDC opportunity picklists (i.e., for Stage and Forecast Category) for an organization.
  # Parameters:   client - a valid SFDC connection client
  #               organization - the organization to search for the picklists
  #               refresh - true, to clear existing values in picklist and then re-insert values; false, to do nothing if there are existing values in the picklist   
  def self.refresh_picklists(client: , organization: , force_refresh: true )
    # puts "\n\n\n*** Running refresh_picklists(force_refresh: #{force_refresh})... @#{Time.current}\n\n\n"
    stages_clm = organization.custom_lists_metadatum.find_by(name: "Stage Name", cs_app_list: true) || organization.custom_lists_metadatum.create(name: "Stage Name", cs_app_list: true)
    forecast_cats_clm = organization.custom_lists_metadatum.find_by(name: "Forecast Category Name", cs_app_list: true) || organization.custom_lists_metadatum.create(name: "Forecast Category Name", cs_app_list: true)

    if force_refresh || stages_clm.custom_lists.blank? || forecast_cats_clm.custom_lists.blank?
      puts "Refreshing custom lists of the available SFDC opportunity picklists (force_refresh=#{force_refresh})..."

      query_statement = "SELECT Id, ApiName, ForecastCategoryName, IsClosed, IsWon, Description, DefaultProbability, IsActive FROM OpportunityStage ORDER BY SortOrder"  
      query_result = SalesforceService.query_salesforce(client, query_statement)
      # puts "*** query: \"#{query_statement}\" ***"
      # puts "result (#{ query_result[:result].size if query_result[:result].present? } rows): #{ query_result }"

      if query_result[:status] == "SUCCESS" && query_result[:result].present?
        stages = Set.new
        forecast_cats = Set.new ["Omitted", "Pipeline", "Best Case", "Commit", "Closed"]
        query_result[:result].each do |stg|
          stages.add(stg.ApiName)
          forecast_cats.add(stg.ForecastCategoryName)
        end

        if force_refresh || stages_clm.custom_lists.blank?
          stages_clm.custom_lists.destroy_all
          stages.each {|s| stages_clm.custom_lists.create(option_value: s) }
        end

        if force_refresh || forecast_cats_clm.custom_lists.blank?
          forecast_cats_clm.custom_lists.destroy_all
          forecast_cats.sort.each {|fc| forecast_cats_clm.custom_lists.create(option_value: fc) }
        end
      elsif query_result[:status] == "ERROR"
        puts "****SFDC**** Error querying SFDC while refreshing opportunity stages and forecast categories picklist. SOQL statement=\"#{query_statement}\" result: #{query_result[:result]} detail: #{query_result[:detail]}"
      elsif query_result[:result].blank?
        puts "****SFDC**** Warning: Did not refresh CS copy of SFDC picklists, because no stages or forecast categories were found. SOQL statement=\"#{query_statement}\" detail: #{query_result[:detail]}"
      end
    else
      puts "****SFDC**** Informational: Did not refresh CS copy of SFDC picklists, because force_refresh is #{force_refresh ? "on" : "off"}#{' and/or Stage picklist has values' if stages_clm.custom_lists.present?}#{' and/or Forecast category picklist has values' if forecast_cats_clm.custom_lists.present?}"
    end
    puts "Refresh opp picklists successful!"
  end

  # Returns the Opportunity Stage Name picklist in an array form of:
  #     [stage_name, custom_list_id]
  # where custom_list_id can be used for option order.
  def self.get_sfdc_opp_stages(organization: )
    return [] if organization.nil?
    stage_name_picklist = organization.custom_lists_metadatum.find_by(name: "Stage Name", cs_app_list: true) if organization.custom_lists_metadatum.present? 
    stage_name_picklist.blank? || stage_name_picklist.custom_lists.blank? ? [] : stage_name_picklist.custom_lists.pluck(:option_value, :id)
  end

  # Returns the Opportunity Forecast Category Name picklist in an array form of:
  #     [forecast_category_name, custom_list_id]
  # where custom_list_id can be used for option order.
  def self.get_sfdc_opp_forecast_categories(organization: )
    return [] if organization.nil?
    forecast_cat_name_picklist = organization.custom_lists_metadatum.find_by(name: "Forecast Category Name", cs_app_list: true) if organization.custom_lists_metadatum.present? 
    forecast_cat_name_picklist.blank? || forecast_cat_name_picklist.custom_lists.blank? ? [] : forecast_cat_name_picklist.custom_lists.pluck(:option_value, :id)
  end
end
