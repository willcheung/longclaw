# == Schema Information
#
# Table name: contacts
#
#  id                 :uuid             not null, primary key
#  account_id         :uuid
#  first_name         :string           default(""), not null
#  last_name          :string           default(""), not null
#  email              :string           default(""), not null
#  phone              :string(32)       default(""), not null
#  title              :string           default(""), not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  source             :string
#  mobile             :string(32)
#  background_info    :text
#  department         :string
#  external_source_id :string
#
# Indexes
#
#  index_contacts_on_account_id            (account_id)
#  index_contacts_on_account_id_and_email  (account_id,email) UNIQUE
#

include ActionView::Helpers::SanitizeHelper   # for sanitize (escape single quotes)

class Contact < ActiveRecord::Base
	belongs_to :account

  ### project_members/projects relations have 2 versions
  # v1: only shows confirmed, similar to old logic without project_members.status column
  # v2: "_all" version, ignores status
  has_many   :project_members, -> { confirmed }, dependent: :destroy, class_name: "ProjectMember"
  has_many   :project_members_all, class_name: "ProjectMember", dependent: :destroy
  has_many   :projects, through: "project_members"
  has_many   :visible_projects, -> { is_active.is_confirmed }, through: "project_members", source: :project
  has_many   :projects_all, through: "project_members_all", source: :project

	validates :email, presence: true, uniqueness: { scope: :account, message: "There's already a contact with the same email." }
  validates_format_of :email,:with => Devise::email_regexp

  scope  :source_from_salesforce, -> { where source: 'Salesforce' }
  scope  :not_source_from_salesforce, -> { where("source != 'Salesforce' OR source is null") }

  # TODO: Create a general visible_to scope for a general "role" checker
  scope :visible_to, -> (user) {
      select('DISTINCT(contacts.*)')
          .joins(:account)
          .where(accounts: {organization_id: user.organization_id})
          .group('contacts.id')
  }

  def is_source_from_salesforce?
    return self.source == "Salesforce"
  end

  # def is_source_from_chrome?
  #   return self.source == "Chrome"
  # end

  def is_internal_user?
    return false
  end

  # Takes the External members found then finds or creates an Account associated with the domains (of their e-mail addresses), finds or creates a Contact for the external members, then adds them to the Stream as suggested members.  
  def self.load(data, project, save_in_db=true)
    contacts = []
    current_org = project.account.organization

    data_hash = data.map { |hash| Hashie::Mash.new(hash) }

    data_hash.each do |d|
      d.newExternalMembers.each do |mem|
        contact = find_or_create_from_email_info(mem.address, mem.personal, project)
        contacts << contact if contact
      end unless d.newExternalMembers.nil?
    end

    return contacts
  end

  def self.find_or_create_from_email_info(address, personal, project, status=ProjectMember::STATUS[:Pending], source=nil)
    org = project.account.organization
    domain = get_domain(address)
    if valid_domain?(domain)
      primary_domain = get_domain_from_subdomain(domain) # roll up subdomains into domains

      ### account and contact setup here can probably be replaced with Model.create_with().find_or_create_by()
      # find account this new member should belong to
      account = org.accounts.find_by_domain(primary_domain)
      # create a new account for this domain if one doesn't exist yet
      unless account
        account = Account.create(
          domain: primary_domain,
          name: primary_domain,
          category: Account::CATEGORY[:Customer], # TODO: 'Customer' may not be in Org's custom list of Account Types (Categories)!!
          address: "",
          website: "http://www.#{primary_domain}",
          owner_id: project.owner_id,
          organization: org,
          created_by: project.owner_id)
        subdomain_msg = primary_domain != domain ? " (subdomain: #{domain})" : ""
        puts "** Created a new account for domain='#{primary_domain}'#{subdomain_msg}, organization='#{org}'. **"
      end

      # find or create contact for this member
      contact = account.contacts.create_with(
        first_name: get_first_name(personal),
        last_name: get_last_name(personal),
        source: source
        ).find_or_create_by(email: address)

      # add member to project as suggested member
      ProjectMember.create(project: project, contact: contact, status: status)

      contact
    else
      puts "** Skipped processing the invalid domain='#{domain}'. **"
    end
  end

  # Takes Contacts (with an e-mail address) in a SFDC account and copies them to a CS account, overwriting all existing Contact fields to each "matched" (same e-mail in the account) Contact.  i.e., if there are multiple Salesforce Contacts with the same e-mail address in the source SFDC account, this loads only one.
  # Parameters:  client - connection to Salesforce
  #              account_id - the CS account to which this copies Contacts
  #              sfdc_account_id - id of SFDC account from which this copies Contacts 
  #              limit (optional) - the max number of Contacts to process
  def self.load_salesforce_contacts(client, account_id, sfdc_account_id, limit=100)
    val = []

    query_statement = "SELECT Id, AccountId, FirstName, LastName, Email, Title, Department, Phone, LeadSource, MobilePhone, Description FROM Contact WHERE AccountId='#{sfdc_account_id}' ORDER BY Email, LastName, FirstName LIMIT #{limit}"

    contacts = SalesforceService.query_salesforce(client, query_statement)
    #contacts = nil #simulate SFDC query error
    unless contacts.blank?  # unless failed Salesforce query
      emails_processed = {}

      # Keep the first contact (alphabetically, by Last then First Name) from contacts with identical e-mails; ignore contacts with no e-mail field
      contacts.each do |c|
        email = Contact.sanitize(c[:Email]) 
        if c[:Email].present? && emails_processed[email].nil?
          firstname = self.capitalize_first_only(c[:FirstName])
          lastname = self.capitalize_first_only(c[:LastName])
          lead_source = c[:LeadSource]
          lead_source = "Salesforce" if lead_source.blank?
          lead_source = "" if lead_source == "ContextSmith"

          val << "('#{account_id}', 
                    #{c[:FirstName].blank? ? '\'\'' : Contact.sanitize(firstname)},
                    #{c[:LastName].blank? ? '\'\'' : Contact.sanitize(lastname)},
                    #{c[:Email].blank? ? '\'\'' : email},
                    #{c[:Title].blank? ? '\'\'' : Contact.sanitize(c[:Title])},
                    #{c[:Department].blank? ? 'null' : Contact.sanitize(c[:Department])},
                    #{c[:Phone].blank? ? '\'\'' : Contact.sanitize(c[:Phone])},
                    #{lead_source.blank? ? 'null' : Contact.sanitize(lead_source)},
                    #{c[:MobilePhone].blank? ? 'null' : Contact.sanitize(c[:MobilePhone])},
                    #{c[:Description].blank? ? 'null' : Contact.sanitize(c[:Description])},
                    #{(c[:LeadSource]=="Chrome" || c[:LeadSource]=="ContextSmith") ? 'null' : "'#{c[:Id]}'" },
                    '#{Time.now}',
                    '#{Time.now}')"
          emails_processed[email] = email 
        end
      end

      insert = 'INSERT INTO "contacts" ("account_id", "first_name", "last_name", "email", "title", "department", "phone", "source", "mobile", "background_info", "external_source_id", "created_at", "updated_at") VALUES'
      on_conflict = 'ON CONFLICT (account_id, email) DO UPDATE SET first_name = EXCLUDED.first_name, last_name = EXCLUDED.last_name, title = EXCLUDED.title, department = EXCLUDED.department, phone = EXCLUDED.phone, source = EXCLUDED.source, mobile = EXCLUDED.mobile, background_info = EXCLUDED.background_info, external_source_id = EXCLUDED.external_source_id, updated_at = EXCLUDED.updated_at'
      values = val.join(', ')
      #puts "And inserting values....  \"#{values}\""

      if !val.empty?
        Contact.transaction do
          # Insert activities into database
          begin
            Contact.connection.execute([insert,values,on_conflict].join(' '))
          rescue ActiveRecord::StatementInvalid => e
            error = ""
            if (e.to_s[0..23]) == "PG::CardinalityViolation" 
              error = "PostgreSQL error: \"#{e}\"" 
            else
              error = "Invalid statement error: \"#{e}\"" 
            end
            puts "ActiveRecord error=#{error}"
            return error
          end
        end
      end
      puts "************* Result of SFDC query \"#{query_statement}\":"
      puts "-> # of rows UPSERTed into Contacts = #{val.count} total *************"
    else  # Salesforce query failure
      return "query=\"#{query_statement}\""  # proprogate query to caller
    end

    nil # successful request
  end

  # Takes Contacts in a CS account and exports them into a SFDC account.  Makes an attempt to identify duplicates (by external_sfdc_id if a Salesforce contact; or account + email) and performs an upsert.  Returns nil if successful, otherwise returns the error (string).
  # Parameters:  client - connection to Salesforce
  #              account_id - the CS account from which this exports contacts
  #              sfdc_account_id - id of SFDC account to which this exports contacts 
  #              limit (optional) - the max number of contacts to process
  def self.export_cs_contacts(client, account_id, sfdc_account_id)
    Account.find(account_id).contacts.each do |c|
      #puts "## Exporting CS contacts to sfdc_account_id = #{ sfdc_account_id } ..."

      sObject_meta = { id: sfdc_account_id, type: "Account" }
      sObject_fields = { FirstName: c.first_name, LastName: c.last_name.empty? ? "(none)" : c.last_name, Email: c.email, Title: c.title, Department: c.department, Phone: c.phone, LeadSource: c.source, MobilePhone: c.mobile, Description: c.background_info }
      #puts "----> sObject_meta:\t #{sObject_meta}\n"
      #puts "----> sObject_fields:\t #{sObject_fields}\n"
      sObject_fields[:external_sfdc_id] = c.external_source_id if c.is_source_from_salesforce?
      results = SalesforceService.update_salesforce(client: client, sObject_meta: sObject_meta, update_type: "contacts", sObject_fields: sObject_fields)
      
      unless results.nil?  # unless failed Salesforce query
        puts "-> a SFDC Contact (#{c.last_name}, #{c.email}) was created/updated from a ContextSmith contact. Contact sObject Id='#{results}'."
      else  # Salesforce query failure
        #return "None"  #no error details to propogate to caller
        return "sObject_fields=#{sObject_fields}"  #parameter details to propogate to caller
      end
    end # End: Account.find(account_id).contacts.each do

    nil # successful creation from request
  end

  private

  # Capitalizes first character and leaves the remaining alone (unlike .capitalize which changes remaining ones to lowercase)
  def self.capitalize_first_only (str)
    str.slice(0,1).capitalize + str.slice(1..-1) if !str.nil?
  end
end
