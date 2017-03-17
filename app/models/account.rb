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

    has_many  :projects, -> { where is_confirmed: true }, dependent: :destroy  #also want is_active:true ?
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

    def self.create_from_clusters(external_members, owner_id, organization_id)
        grouped_external_members = external_members.group_by{ |x| get_domain(x.address) }
        existing_accounts = Account.where(domain: grouped_external_members.keys, organization_id: organization_id).includes(:contacts)
        existing_domains = existing_accounts.map(&:domain)

        # Create missing accounts
        (grouped_external_members.keys - existing_domains).each do |d|
            if valid_domain?(d)
                subdomain = d
                d = get_domain_from_subdomain(subdomain) # roll up subdomains into domains
                org_info = get_org_info(d)

                account = Account.new(domain: d, 
                                      name: org_info[0], 
                                      category: "Customer",
                                      address: org_info[1],
                                      website: "http://www.#{d}",
                                      owner_id: owner_id, 
                                      organization_id: organization_id,
                                      created_by: owner_id)
                account.save(validate: false)

                subdomain_msg = d != subdomain ? " (subdomain: #{subdomain})" : ""
                puts "** Created a new account for domain='#{d}'#{subdomain_msg}, organization_id='#{organization_id}'. **"

                grouped_external_members[d].each do |c|
                    # Create contacts
                    account.contacts.create(first_name: get_first_name(c.personal),
                                            last_name: get_last_name(c.personal),
                                            email: c.address)
                end
            else
                puts "** Skipped processing the invalid domain='#{d}'. **"
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

    # Updates all mapped custom fields of a single SF account -> CS account
    def self.load_salesforce_fields(salesforce_client, account_id, sfdc_account_id, account_custom_fields)
        unless (salesforce_client.nil? or account_id.nil? or sfdc_account_id.nil? or account_custom_fields.nil? or account_custom_fields.empty?)
            account_custom_field_names = []
            account_custom_fields.each { |cf| account_custom_field_names << cf.salesforce_field}

            query_statement = "SELECT " + account_custom_field_names.join(", ") + " FROM Account WHERE Id = '#{sfdc_account_id}' LIMIT 1"
            sObjects_result = SalesforceService.query_salesforce(salesforce_client, query_statement)

            unless sObjects_result.nil?
                sObj = sObjects_result.first
                account_custom_fields.each do |cf|
                    #csfield = CustomField.find_by(custom_fields_metadata_id: cf.id, customizable_uuid: account_id)
                    #print "----> CS_fieldname=\"", cf.name, "\" SF_fieldname=\"", cf.salesforce_field, "\"\n"
                    #print "   .. CS_fieldvalue=\"", csfield.value, "\" SF_fieldvalue=\"", sObj[cf.salesforce_field], "\"\n"
                    CustomField.find_by(custom_fields_metadata_id: cf.id, customizable_uuid: account_id).update(value: sObj[cf.salesforce_field])
                end
            else
                return "account_custom_field_names=" + account_custom_field_names.to_s # proprogate list of field names to caller
            end
        end

        nil # successful request
    end

    private

    # Create all custom fields for a new account
    def create_custom_fields
        CustomFieldsMetadatum.where(organization:self.organization, entity_type: "Account").each { |cfm| CustomField.create(organization:self.organization, custom_fields_metadatum:cfm, customizable:self) }
    end
end
