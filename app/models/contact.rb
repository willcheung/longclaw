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
#  alt_email       :string
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
  has_many   :project_members, -> { where "project_members.status = #{ProjectMember::STATUS[:Confirmed]}" }, dependent: :destroy
  has_many   :project_members_all, class_name: "ProjectMember", dependent: :destroy
  has_many   :projects, through: "project_members"
  has_many   :projects_all, through: "project_members_all", source: :project

	validates :email, presence: true, uniqueness: { scope: :account, message: "There's already a contact with the same email." }

  def self.load(data, project, save_in_db=true)
    contacts = []
    current_org = project.account.organization

    data_hash = data.map { |hash| Hashie::Mash.new(hash) }

    data_hash.each do |d|
      d.newExternalMembers.each do |mem|
        domain = get_domain(mem.address)
        # find account this new member should belong to
        account = Account.find_by(domain: domain, organization: current_org)
        unless account
          # create a new account for this domain if one doesn't exist yet
          account = Account.create(domain: domain, 
                                name: domain, 
                                category: "Customer",
                                address: "",
                                website: "http://www.#{domain}",
                                owner_id: project.owner_id, 
                                organization: current_org,
                                created_by: project.owner_id)
        end
        # find or create contact for this member
        contact = account.contacts.find_or_create_by(
          first_name: get_first_name(mem.personal),
          last_name: get_last_name(mem.personal),
          email: mem.address)
        # add member to project
        project.project_members.create(contact_id: contact.id, status: ProjectMember::STATUS[:Pending])

        contacts << contact
      end unless d.newExternalMembers.nil?
    end

    return contacts
  end

	def is_internal_user?
 		false
  end
end
