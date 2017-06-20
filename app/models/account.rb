# == Schema Information
#
# Table name: accounts
#
#  id                :uuid             not null, primary key
#  name              :string           default(""), not null
#  description       :text             default("")
#  website           :string
#  owner_id          :uuid
#  phone             :string
#  address           :text
#  created_by        :uuid
#  updated_by        :uuid
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  organization_id   :uuid
#  notes             :text
#  status            :string           default("Active")
#  domain            :string(64)       default(""), not null
#  category          :string           default("Customer")
#  deleted_at        :datetime
#  revenue_potential :decimal(14, 2)
#
# Indexes
#
#  index_accounts_on_deleted_at  (deleted_at)
#

include Utils
include ContextSmithParser

class Account < ActiveRecord::Base
    after_create  :create_custom_fields

    has_many  :projects, -> { is_confirmed }, dependent: :destroy # should this also include Project.is_active scope?
    has_many  :contacts, dependent: :destroy
    has_many  :activities, :through => :projects
    belongs_to  :organization
    belongs_to  :user, foreign_key: "owner_id"

    has_many :salesforce_accounts, foreign_key: "contextsmith_account_id", dependent: :nullify
    has_many :custom_fields, as: :customizable, foreign_key: "customizable_uuid", dependent: :destroy

    validates :name, presence: true, uniqueness: { scope: :organization, message: "There's already an account with the same name." }

    # TODO: Create a general visible_to scope for a general "role" checker
    scope :visible_to, -> (user) {
        select('DISTINCT(accounts.*)')
            .where(organization_id: user.organization_id)
            .group('accounts.id')
    }

    STATUS = %w(Active Inactive Dead)
    CATEGORY = { Competitor: 'Competitor', Customer: 'Customer', Investor: 'Investor', Integrator: 'Integrator', Partner: 'Partner', Press: 'Press', Prospect: 'Prospect', Reseller: 'Reseller', Vendor: 'Vendor', Other: 'Other' }
    MAPPABLE_FIELDS_META = [ "name", "description", "website", "phone", "address", "notes", "domain", "category", "revenue_potential" ]

    def self.create_from_clusters(external_members, owner_id, organization_id)
        domain_grouped_external_members = external_members.group_by { |x| get_domain(x.address) }
        domain_grouped_external_members.keep_if do |domain, person_array|
            valid = valid_domain?(domain)
            p "** Skipped processing the invalid domain='#{domain}'. **" if !valid
            valid
        end
        grouped_external_members = Hash.new(Array.new)
        domain_grouped_external_members.each do |domain, person_array|
            primary_domain = get_domain_from_subdomain(domain) # roll up subdomains into one primary domain
            p "** subdomain '#{domain}' detected! external members to be merged with primary domain '#{primary_domain}'. **" if primary_domain != domain
            grouped_external_members[primary_domain] += person_array
        end
        existing_accounts = Account.where(domain: grouped_external_members.keys, organization_id: organization_id).includes(:contacts)
        existing_domains = existing_accounts.map(&:domain)

        # Create missing accounts
        (grouped_external_members.keys - existing_domains).each do |domain|
            org_info = get_org_info(domain)

            account = Account.new(domain: domain, 
                                  name: org_info[0], 
                                  category: Account::CATEGORY[:Customer], # TODO: 'Customer' may not be in Org's custom list of Account Types (Categories)!!
                                  address: org_info[1],
                                  website: "http://www.#{domain}",
                                  owner_id: owner_id, 
                                  organization_id: organization_id,
                                  created_by: owner_id)
            account.save(validate: false)

            puts "** Created a new account for domain='#{domain}', organization_id='#{organization_id}'. **"

            grouped_external_members[domain].each do |c|
                # Create contacts
                account.contacts.create(first_name: get_first_name(c.personal),
                                        last_name: get_last_name(c.personal),
                                        email: c.address)
            end
        end

        # Create contacts for existing accounts
        existing_accounts.each do |a|
            existing_emails = a.contacts.map(&:email)
            external_emails = grouped_external_members[a.domain].map(&:address)
            missing_emails = external_emails - existing_emails

            grouped_external_members[a.domain].each do |c|
                if missing_emails.include?(c.address)
                    a.contacts.create(first_name: get_first_name(c.personal),
                                      last_name: get_last_name(c.personal),
                                      email: c.address)
                end
            end
        end
    end

    # Updates all (standard) CS Account fields from all mapped SFDC Account fields.
    # Parameters:   client - connection to Salesforce
    #               accounts - collection of CS Accounts to process
    #               sfdc_fields_mapping - A list of [Mapped SFDC Account field name, CS Account field name] pairs
    # Returns:   A hash that represents the execution status/result. Consists of:
    #             status - "SUCCESS" if load was successful; otherwise, "ERROR" 
    #             result - if status == "ERROR", contains the title of the error
    #             detail - if status == "ERROR", contains the details of the error
    def self.update_fields_from_sfdc(client: , accounts: , sfdc_fields_mapping: )
        result = nil

        unless (client.nil? || accounts.nil? || sfdc_fields_mapping.blank?)
            sfdc_fields_mapping = sfdc_fields_mapping.to_h
            sfdc_ids_mapping = accounts.collect { |a| a.salesforce_accounts.first.nil? ? nil : [a.salesforce_accounts.first.salesforce_account_id, a.id] }.compact  # a list of [linked SFDC sObject Id, CS Account id] pairs
            sfdc_ids_mapping = sfdc_ids_mapping.to_h

            # puts "sfdc_fields_mapping: #{ sfdc_fields_mapping }"
            # puts "SFDC account field names: #{ sfdc_fields_mapping.keys }"
            # puts "sfdc_ids_mapping: #{ sfdc_ids_mapping }"
            # puts "SFDC account ids: #{ sfdc_ids_mapping.keys }"
            unless sfdc_ids_mapping.empty? 
                query_statement = "SELECT Id, " + sfdc_fields_mapping.keys.join(", ") + " FROM Account WHERE Id IN ('" + sfdc_ids_mapping.keys.join("', '") + "')"
                query_result = SalesforceService.query_salesforce(client, query_statement)
                # puts "*** query: \"#{query_statement}\" ***"
                # puts "result (#{ query_result[:result].size if query_result[:result].present? } rows): #{ query_result }"

                if query_result[:status] == "SUCCESS"
                    changed_values_hash_list = []
                    query_result[:result].each do |r|
                        # CS_UUID = sfdc_ids_mapping[r.Id] , SFDC_Id = r.Id
                        sfdc_fields_mapping.each do |k,v|
                            # k (SFDC field name) , v (CS field name), r[k] (SFDC field value)
                            if r[k].is_a?(Restforce::Mash) # the value is a Salesforce sObject
                                sfdc_val = []
                                r[k].each { |k,v| sfdc_val.push(v.to_s) if v.present? }
                                sfdc_val = sfdc_val.join(", ")
                            else
                                sfdc_val = r[k]
                            end
                            changed_values_hash_list.push({ sfdc_ids_mapping[r.Id] => { v => sfdc_val } })
                        end
                    end
                    puts "changed_values_hash_list: #{ changed_values_hash_list }"

                    changed_values_hash_list.each { |h| Account.update(h.keys, h.values) }
                    result = { status: "SUCCESS" }
                else
                    result = { status: "ERROR", result: query_result[:result], detail: query_result[:detail] + " query_statement=" + query_statement }
                end
            else  # No mapped Accounts -> SFDC Accounts
                result = { status: "SUCCESS" }  
            end
        else
            if client.nil?
                puts "** ContextSmith error: Parameter 'client' passed to Account.update_fields_from_sfdc is invalid!"
                result = { status: "ERROR", result: "ContextSmith Error", detail: "A parameter passed to an internal function is invalid." }
            else
                # Ignores if other parameters were not passed properly to update_fields_from_sfdc
                result = { status: "SUCCESS", result: "Warning: no fields updated.", detail: "No SFDC fields to import!" }
            end
        end

        result
    end

    # Updates all custom CS Account fields mapped to SFDC account fields for a single CS account/SFDC account pair.
    # Parameters:   client - connection to Salesforce
    #               account_id - CS account id          
    #               sfdc_account_id - SFDC account sObjectId
    #               account_custom_fields - ActiveRecord::Relation that represents the custom fields (CustomFieldsMetadatum) of the CS account.
    # Returns:   A hash that represents the execution status/result. Consists of:
    #             status - "SUCCESS" if load was successful; otherwise, "ERROR" 
    #             result - if status == "ERROR", contains the title of the error
    #             detail - if status == "ERROR", contains the details of the error
    def self.load_salesforce_fields(client: , account_id: , sfdc_account_id: , account_custom_fields: )
        result = nil

        unless (client.nil? || account_id.nil? || sfdc_account_id.nil? || account_custom_fields.blank?)
            account_custom_field_names = account_custom_fields.collect { |cf| cf.salesforce_field }

            query_statement = "SELECT " + account_custom_field_names.join(", ") + " FROM Account WHERE Id = '#{sfdc_account_id}' LIMIT 1"
            query_result = SalesforceService.query_salesforce(client, query_statement)

            if query_result[:status] == "SUCCESS"
                sObj = query_result[:result].first
                account_custom_fields.each do |cf|
                    # csfield = CustomField.find_by(custom_fields_metadata_id: cf.id, customizable_uuid: account_id)
                    # print "----> CS_fieldname=\"", cf.name, "\" SF_fieldname=\"", cf.salesforce_field, "\"\n"
                    # print "   .. CS_fieldvalue=\"", csfield.value, "\" SF_fieldvalue=\"", sObj[cf.salesforce_field], "\"\n"
                    CustomField.find_by(custom_fields_metadata_id: cf.id, customizable_uuid: account_id).update(value: sObj[cf.salesforce_field])
                end
                result = { status: "SUCCESS" }
            else
                result = { status: "ERROR", result: query_result[:result], detail: query_result[:detail] + " account_custom_field_names=" + account_custom_field_names.to_s }
            end
        else
            if client.nil?
                puts "** ContextSmith error: Parameter 'client' passed to Account.load_salesforce_fields is invalid!"
                result = { status: "ERROR", result: "ContextSmith Error", detail: "A parameter passed to an internal function is invalid." }
            else
                # Ignores if other parameters were not passed properly to load_salesforce_fields
                result = { status: "SUCCESS", result: "Warning: no fields updated.", detail: "No SFDC fields to import!" }
            end
        end

        result
    end

    private

    # Create all custom fields for a new account
    def create_custom_fields
        CustomFieldsMetadatum.where(organization:self.organization, entity_type: "Account").each { |cfm| CustomField.create(organization:self.organization, custom_fields_metadatum:cfm, customizable:self) }
    end
end
