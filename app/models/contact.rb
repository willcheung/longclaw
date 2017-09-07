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
#  buyer_role         :string
#
# Indexes
#
#  index_contacts_on_account_id            (account_id)
#  index_contacts_on_account_id_and_email  (account_id,email) UNIQUE
#

include ActionView::Helpers::SanitizeHelper   # for sanitize (escape single quotes)

class Contact < ActiveRecord::Base
  before_save :downcase_email

	belongs_to :account

  ### project_members/projects relations have 2 versions
  # v1: only shows confirmed, similar to old logic without project_members.status column
  # v2: "_all" version, ignores status
  has_many   :project_members, -> { confirmed }, class_name: "ProjectMember", dependent: :destroy
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

  PHONE_LEN_MAX = 32
  MOBILE_LEN_MAX = 32
  ROLE = { Economic: 'Economic', Technical: 'Technical', Champion: 'Champion', DecisionMaker: 'Decision Maker', Influencer: 'Influencer', User: 'User', Blocker: 'Blocker', Other: 'Other' }
  MAPPABLE_FIELDS_META = { "first_name" => "First Name", "last_name" => "Last Name", "email" => "E-mail", "phone" => "Phone", "mobile" => "Mobile Phone", "title" => "Title", "background_info" => "Notes / Background Info", "department" => "Department", "buyer_role" => "Buyer Role" }

  def is_source_from_salesforce?
    return self.source == "Salesforce"
  end

  def is_internal_user?
    return false
  end

  # Takes the External members found then finds or creates an Account associated with the domains (of their e-mail addresses), finds or creates a Contact for the external members, then adds them to the Opportunity as suggested members.  
  def self.load(data, project, save_in_db=true)
    contacts = []
    current_org = project.account.organization

    data_hash = data.map { |hash| Hashie::Mash.new(hash) }

    data_hash.each do |d|
      d.newExternalMembers.each do |mem|
        contact = find_or_create_from_email_info(mem.address, mem.personal, project, ProjectMember::STATUS[:Pending], "Email")
        contacts << contact if contact
      end unless d.newExternalMembers.nil?
    end

    return contacts
  end

  def self.find_or_create_from_email_info(address, personal, project, status=ProjectMember::STATUS[:Pending], source=nil)
    address = address.downcase
    org = project.account.organization
    domain = get_domain(address)
    puts "** Skipped creating Contact for #{address}, invalid domain='#{domain}'. **" && return unless valid_domain?(domain)

    # find account this new member should belong to
    primary_domain = get_domain_from_subdomain(domain) # roll up subdomains into domains
    account = org.accounts.find_by_domain(primary_domain) || org.accounts.find_by_name(primary_domain)
    if account.blank?
      # try to find a contact with matching email domain
      contact = org.contacts.where("email LIKE '%@#{domain}'").first || org.contacts.where("email LIKE '%@#{primary_domain}'").first
      account = contact.account if contact.present?
    end
    puts "** Skipped creating Contact for #{address}, no Account found! **" && return if account.blank?

    # find or create contact for this member
    contact = account.contacts.create_with(
      first_name: get_first_name(personal),
      last_name: get_last_name(personal),
      source: source
    ).find_or_create_by(email: address)

    # add member to project as suggested member
    ProjectMember.create(project: project, contact: contact, status: status)

    contact
  end

  # Takes Contacts (with an e-mail address) in a SFDC account and imports them to a CS account, merging existing values in CS Contact fields for each "matched" Contact (same e-mail).  If there are multiple Salesforce Contacts with the same e-mail address in the source SFDC account, this loads only one. Note: Contact merge will only copy the value from the SFDC Contact field if there's no existing value in the matched CS Contact.
  # Parameters:  client - connection to Salesforce
  #              account_id - the CS account to which to import Contacts
  #              sfdc_account_id - id of SFDC account from which to import Contacts 
  #              limit (optional) - the max number of Contacts to process
  # Returns:   A hash that represents the execution status/result. Consists of:
  #             status - string "SUCCESS" if successful, or "ERROR" otherwise
  #             result - if status == "SUCCESS", contains the result of the operation; otherwise, contains the title of the error
  #             detail - Contains any error or informational/warning messages.
  def self.load_salesforce_contacts(client, account_id, sfdc_account_id, limit=100)
    val = []
    result = nil
    # return { status: "ERROR", result: "Simulated SFDC error", detail: "Simulated detail" }

    query_statement = "SELECT Id, AccountId, FirstName, LastName, Email, Title, Department, Phone, MobilePhone FROM Contact WHERE AccountId='#{sfdc_account_id}' ORDER BY Email, LastName, FirstName LIMIT #{limit}"  # Unused: Description, LeadSource

    query_result = SalesforceService.query_salesforce(client, query_statement)

    if query_result[:status] == "SUCCESS"
      emails_processed = {}

      # Keep the first contact (alphabetically, by Last then First Name) from contacts with identical e-mails; ignore contacts with no e-mail field
      query_result[:result].each do |c|
        email = Contact.sanitize(c[:Email]).downcase
        if c[:Email].present? && emails_processed[email].nil?
          firstname = self.capitalize_first_only(c[:FirstName])
          lastname = self.capitalize_first_only(c[:LastName])
          #lead_source = c[:LeadSource]
          #lead_source = "Salesforce" if lead_source.blank?
          #lead_source = "" if lead_source == "ContextSmith"

          val << "('#{account_id}', 
                    #{c[:FirstName].blank? ? '\'\'' : Contact.sanitize(firstname)},
                    #{c[:LastName].blank? ? '\'\'' : Contact.sanitize(lastname)},
                    #{c[:Email].blank? ? '\'\'' : email},
                    #{c[:Title].blank? ? '\'\'' : Contact.sanitize(c[:Title])},
                    #{c[:Department].blank? ? 'null' : Contact.sanitize(c[:Department])},
                    #{c[:Phone].blank? ? '\'\'' : Contact.sanitize(c[:Phone][0...PHONE_LEN_MAX])},
                    #{c[:MobilePhone].blank? ? 'null' : Contact.sanitize(c[:MobilePhone][0...MOBILE_LEN_MAX])},
                    'Salesforce',
                    #{"'#{c[:Id]}'"},
                    '#{Time.now}',
                    '#{Time.now}')"
          ####### Unused: 
                    #{c[:Description].blank? ? 'null' : Contact.sanitize(c[:Description])},
                    #{lead_source.blank? ? 'null' : Contact.sanitize(lead_source)},
                    #{(c[:LeadSource]=="Chrome" || c[:LeadSource]=="ContextSmith") ? 'null' : "'#{c[:Id]}'" },
          emails_processed[email] = email 
        end
      end

      insert = 'INSERT INTO "contacts" ("account_id", "first_name", "last_name", "email", "title", "department", "phone", "mobile", "source", "external_source_id", "created_at", "updated_at") VALUES'  # Unused: "background_info" 
      on_conflict = 'ON CONFLICT (account_id, email) DO UPDATE SET first_name = CASE WHEN LENGTH(contacts.first_name::text) > 0 THEN contacts.first_name ELSE EXCLUDED.first_name END, last_name = CASE WHEN LENGTH(contacts.last_name::text) > 0 THEN contacts.last_name ELSE EXCLUDED.last_name END, title = CASE WHEN LENGTH(contacts.title::text) > 0 THEN contacts.title ELSE EXCLUDED.title END, department = CASE WHEN LENGTH(contacts.department::text) > 0 THEN contacts.department ELSE EXCLUDED.department END, phone = CASE WHEN LENGTH(contacts.phone::text) > 0 THEN contacts.phone ELSE EXCLUDED.phone END, mobile = CASE WHEN LENGTH(contacts.mobile::text) > 0 THEN contacts.mobile ELSE EXCLUDED.mobile END, external_source_id = CASE WHEN LENGTH(contacts.external_source_id::text) > 0 THEN contacts.external_source_id ELSE EXCLUDED.external_source_id END, updated_at = CASE WHEN LENGTH(contacts.updated_at::text) > 0 THEN contacts.updated_at ELSE EXCLUDED.updated_at END'  # Unused: background_info = EXCLUDED.background_info, source = EXCLUDED.source 
      values = val.join(', ')
      # puts "And inserting values....  \"#{values}\""

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
            puts "ActiveRecord error in Contact.load_salesforce_contacts()=#{error}"
            return { status: "ERROR", result: "ActiveRecord error in Contact.load_salesforce_contacts()!", detail: "#{ error } Query: #{ query_statement }" }
          end
        end
      end
      # puts "**** Result of SFDC query \"#{query_statement}\":"
      # puts "-> # of rows UPSERTed into Contacts = #{val.count} total ****"
      result = { status: "SUCCESS", result: "Rows imported from SFDC into CS Contacts = #{val.count}", detail: "#{ query_result[:detail] }" }
    else  # SFDC query failure
      result = { status: "ERROR", result: query_result[:result], detail: "#{ query_result[:detail] } Query: #{ query_statement }" }
    end

    result
  end

  # Takes Contacts in a CS account and exports them into a SFDC account.  Makes an attempt to identify duplicates (by external_sfdc_id if a Salesforce contact; or account + email) and performs an upsert.  Note: If a value exists in the CS Contact field, then this value will overwrite the corresponding field in the matched target SFDC Contact.
  # Parameters: client - connection to Salesforce
  #             account_id - the CS account from which this exports contacts
  #             sfdc_account_id - id of SFDC account to which this exports contacts 
  #             limit (optional) - the max number of contacts to process
  # Returns:   A hash that represents the execution status/result. Consists of:
  #             status - "SUCCESS" if operation is successful with no errors (contact exported or no contacts to export); ERROR" if any error occurred during the operation (including partial successes)
  #             result - a list of sObject SFDC id's that were successfully created in SFDC, or an empty list if none were created.
  #             detail - a list of all errors, or an empty list if no errors occurred. 
  def self.export_cs_contacts(client, account_id, sfdc_account_id)
    result = { status: "SUCCESS", result: [], detail: [] }
    # return { status: "ERROR", result: "Simulated SFDC error", detail: "Simulated detail" }

    Account.find(account_id).contacts.each do |c|
      #puts "## Exporting CS contacts to sfdc_account_id = #{ sfdc_account_id } ..."

      sObject_meta = { id: sfdc_account_id, type: "Account" }
      sObject_fields = { FirstName: c.first_name, LastName: c.last_name, Email: c.email, Title: c.title, Department: c.department, Phone: c.phone, MobilePhone: c.mobile }
      # Unused: LeadSource: c.source, Description: c.background_info
      #puts "----> sObject_meta:\t #{sObject_meta}\n"
      #puts "----> sObject_fields:\t #{sObject_fields}\n"
      sObject_fields[:external_sfdc_id] = c.external_source_id if c.is_source_from_salesforce?
      update_result = SalesforceService.update_salesforce(client: client, update_type: "contacts", sObject_meta: sObject_meta, sObject_fields: sObject_fields)

      if update_result[:status] == "SUCCESS"
        puts "-> a SFDC Contact (#{c.last_name}, #{c.first_name}, #{c.email}) was created/updated from a ContextSmith contact. Contact sObject Id='#{ update_result[:result] }'."
        # don't set result[:status] back to SUCCESS if export for another contact failed
        result[:result] << update_result[:result]
        result[:detail] << update_result[:detail]  # may contain messages, even with SUCCESS
      else  # Salesforce query failure
        # puts "** #{ update_result[:result] } Details: #{ update_result[:detail] }."
        result[:status] = "ERROR"
        result[:result] << update_result[:result]
        result[:detail] << update_result[:detail] + " sObject_fields=#{ sObject_fields }"
      end
    end # End: Account.find(account_id).contacts.each do

    result
  end

  private

  # Capitalizes first character and leaves the remaining alone (unlike .capitalize which changes remaining ones to lowercase)
  def self.capitalize_first_only (str)
    str.slice(0,1).capitalize + str.slice(1..-1) if !str.nil?
  end

  def downcase_email
    self.email.downcase!
  end
end
