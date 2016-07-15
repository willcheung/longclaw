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
	has_many :project_members, dependent: :destroy
	has_many :projects, through: "project_members"

	validates :email, presence: true, uniqueness: { scope: :account, message: "There's already a contact with the same email." }

  def self.load(data, project, save_in_db=true)
    contacts = []
    val = []

    data_hash = data.map { |hash| Hashie::Mash.new(hash) }

    data_hash.each do |d|
      d.newExternalMembers.each do |mem|
        contact = project.account.contacts.find_or_create_by(
          first_name: get_first_name(mem.personal),
          last_name: get_last_name(mem.personal),
          email: mem.address)

        project.project_members.create(contact_id: contact.id)

        contacts << contact
      end unless d.newExternalMembers.nil?
    end

    return contacts
  end

	def is_internal_user?
 		false
  end
end
