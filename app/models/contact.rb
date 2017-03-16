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
#  index_contacts_on_account_id  (account_id)
#

class Contact < ActiveRecord::Base
	belongs_to :account

  ### project_members/projects relations have 2 versions
  # v1: only shows confirmed, similar to old logic without project_members.status column
  # v2: "_all" version, ignores status
  has_many   :project_members, -> { confirmed }, dependent: :destroy, class_name: "ProjectMember"
  has_many   :project_members_all, class_name: "ProjectMember", dependent: :destroy
  has_many   :projects, through: "project_members"
  has_many   :projects_all, through: "project_members_all", source: :project

	validates :email, presence: true, uniqueness: { scope: :account, message: "There's already a contact with the same email." }

  # Takes the External members found then finds or creates an Account associated with the domains (of their e-mail addresses), finds or creates a Contact for the external members, then adds them to the Stream as suggested members.  
  def self.load(data, project, save_in_db=true)
    contacts = []
    current_org = project.account.organization

    data_hash = data.map { |hash| Hashie::Mash.new(hash) }

    data_hash.each do |d|
      d.newExternalMembers.each do |mem|
        domain = get_domain(mem.address)
        if valid_domain?(domain)
          subdomain = domain
          domain = get_domain_from_subdomain(subdomain) # roll up subdomains into domains

          ### account and contact setup here can probably be replaced with Model.create_with().find_or_create_by()
          # find account this new member should belong to
          account = Account.find_by(domain: domain, organization: current_org)
          # create a new account for this domain if one doesn't exist yet
          unless account
            account = Account.create(
              domain: domain,
              name: domain,
              category: "Customer",
              address: "",
              website: "http://www.#{domain}",
              owner_id: project.owner_id,
              organization: current_org,
              created_by: project.owner_id)
            subdomain_msg = domain != subdomain ? " (subdomain: #{subdomain})" : ""
                puts "** Created a new account for domain='#{domain}'#{subdomain_msg}, organization='#{current_org}'. **"
          end

          # find contact for this member
          contact = account.contacts.find_by_email(mem.address)
          # create contact for this member if one doesn't exist yet
          contact = account.contacts.create(
            first_name: get_first_name(mem.personal),
            last_name: get_last_name(mem.personal),
            email: mem.address) unless contact

          # add member to project as suggested member
          project.project_members.create(contact_id: contact.id, status: ProjectMember::STATUS[:Pending])

          contacts << contact
        else
        	puts "** Skipped creating a new account for invalid domain='#{domain}'. **"
        end
      end unless d.newExternalMembers.nil?
    end

    return contacts
  end

	def is_internal_user?
		return false
	end
end
