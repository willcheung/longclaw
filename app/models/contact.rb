# == Schema Information
#
# Table name: contacts
#
#  id              :uuid             not null, primary key
#  account_id      :uuid
#  first_name      :string           default(""), not null
#  last_name       :string           default(""), not null
#  email           :string           default(""), not null
#  phone           :string(32)       default(""), not null
#  title           :string           default(""), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  source          :string
#  mobile          :string(32)
#  background_info :text
#  department      :string
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

  scope  :imported_from_salesforce, -> { where source: 'Salesforce' }

  # TODO: Create a general visible_to scope for a general "role" checker
  scope :visible_to, -> (user) {
      select('DISTINCT(contacts.*)')
          .joins(:account)
          .where(accounts: {organization_id: user.organization_id})
          .group('contacts.id')
  }

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
      subdomain = domain
      domain = get_domain_from_subdomain(subdomain) # roll up subdomains into domains

      ### account and contact setup here can probably be replaced with Model.create_with().find_or_create_by()
      # find account this new member should belong to
      account = org.accounts.find_by_domain(domain)
      # create a new account for this domain if one doesn't exist yet
      unless account
        account = Account.create(
          domain: domain,
          name: domain,
          category: "Customer",
          address: "",
          website: "http://www.#{domain}",
          owner_id: project.owner_id,
          organization: org,
          created_by: project.owner_id)
        subdomain_msg = domain != subdomain ? " (subdomain: #{subdomain})" : ""
        puts "** Created a new account for domain='#{domain}'#{subdomain_msg}, organization='#{org}'. **"
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

	def is_internal_user?
		return false
	end

  # Takes Contacts in SFDC account and copies them into CS accounts mapped to it, overwriting all existing contact fields
  # Parameters:  client - connection to Salesforce
  #              account_id - CS account to load contacts to
  #              sfdc_id - id of SFDC account to load contacts from
  def self.load_salesforce_contacts(client, account_id, sfdc_id, limit=100)
    val = []

    query_statement = "SELECT Id, AccountId, FirstName, LastName, Email, Title, Department, Phone, MobilePhone, Description FROM Contact WHERE AccountId='#{sfdc_id}' ORDER BY Email, FirstName, LastName LIMIT #{limit}"

    contacts = SalesforceService.query_salesforce(client, query_statement)
    #contacts = nil #simulate SFDC query error
    unless contacts.blank?  # unless failed Salesforce query
      emails_processed = {}

      # Keep the first contact (alphabetically, by First then Last Name) from contacts with identical e-mails; ignore contacts with no e-mail field
      contacts.each do |c|
        email = Contact.sanitize(c[:Email])
        if c[:Email].present? && emails_processed[email].nil?
          firstname = self.capitalize_first_only(c[:FirstName])
          lastname = self.capitalize_first_only(c[:LastName])
          val << "('#{account_id}', 
                    #{c[:FirstName].blank? ? '\'\'' : Contact.sanitize(firstname)},
                    #{c[:LastName].blank? ? '\'\'' : Contact.sanitize(lastname)},
                    #{c[:Email].blank? ? '\'\'' : email},
                    #{c[:Title].blank? ? '\'\'' : Contact.sanitize(c[:Title])},
                    #{c[:Department].blank? ? 'null' : Contact.sanitize(c[:Department])},
                    #{c[:Phone].blank? ? '\'\'' : Contact.sanitize(c[:Phone])},
                    'Salesforce',
                    #{c[:MobilePhone].blank? ? 'null' : Contact.sanitize(c[:MobilePhone])},
                    #{c[:Description].blank? ? 'null' : Contact.sanitize(c[:Description])},
                    '#{Time.now}', '#{Time.now}')"
          emails_processed[email] = email 
        end
      end

      insert = 'INSERT INTO "contacts" ("account_id", "first_name", "last_name", "email", "title", "department", "phone", "source", "mobile", "background_info", "created_at", "updated_at") VALUES'
      on_conflict = 'ON CONFLICT (account_id, email) DO UPDATE SET first_name = EXCLUDED.first_name, last_name = EXCLUDED.last_name, title = EXCLUDED.title, department = EXCLUDED.department, phone = EXCLUDED.phone, source = EXCLUDED.source, mobile = EXCLUDED.mobile, background_info = EXCLUDED.background_info, updated_at = EXCLUDED.updated_at'
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

  private

  # Capitalizes first character and leaves the remaining alone (unlike .capitalize which changes remaining ones to lowercase)
  def self.capitalize_first_only (str)
    str.slice(0,1).capitalize + str.slice(1..-1) if !str.nil?
  end
end
