# == Schema Information
#
# Table name: accounts
#
#  id              :uuid             not null, primary key
#  name            :string           default(""), not null
#  description     :text             default("")
#  website         :string
#  owner_id        :uuid
#  phone           :string
#  address         :text
#  created_by      :uuid
#  updated_by      :uuid
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  organization_id :uuid
#  notes           :text
#  status          :string           default("Active")
#  domain          :string(64)       default(""), not null
#  category        :string           default("Customer")
#  deleted_at      :datetime
#
# Indexes
#
#  index_accounts_on_deleted_at  (deleted_at)
#

include Utils
include ContextSmithParser

class Account < ActiveRecord::Base
    acts_as_paranoid

	has_many	:projects, -> { where is_confirmed: true }, dependent: :destroy
    has_many  :contacts, dependent: :destroy
    has_many  :activities, :through => :projects
	belongs_to	:organization
	belongs_to	:user, foreign_key: "owner_id"

	validates :name, presence: true, uniqueness: { scope: :organization, message: "There's already an account with the same name." }

	STATUS = %w(Active Inactive Dead)
  CATEGORY = { Customer: 'Customer', Partner: 'Partner', Prospect: 'Prospect', Vendor: 'Vendor', Other: 'Other' }

	def self.create_from_clusters(external_members, owner_id, organization_id)
		grouped_external_members = external_members.group_by{ |x| get_domain(x.address) }
		existing_accounts = Account.where(domain: grouped_external_members.keys, organization_id: organization_id).includes(:contacts)
		existing_domains = existing_accounts.map(&:domain)

		# Create missing accounts
		(grouped_external_members.keys - existing_domains).each do |a|
      org_info = get_org_info(a)

     	account = Account.new(domain: a, 
     								 				name: org_info[0], 
                            category: "Customer",
                            address: org_info[1],
                            website: "http://www.#{a}",
     								 				owner_id: owner_id, 
     								 				organization_id: organization_id,
     								 				created_by: owner_id)
     	account.save(validate: false)

     	grouped_external_members[a].each do |c|
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
end
