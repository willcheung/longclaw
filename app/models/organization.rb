# == Schema Information
#
# Table name: organizations
#
#  id         :uuid             not null, primary key
#  name       :string
#  domain     :string
#  is_active  :boolean          default(TRUE)
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  owner_id   :uuid
#

class Organization < ActiveRecord::Base
	has_many :users
	has_many :accounts

	# Returns new_org if there's no existing one.  If there is, return existing one.
	def create_user_organization(domain, user)
		new_org = Organization.new(name: "Test Org",
														 	 domain: domain,
														 	 owner_id: user.id)
    
    existing_org = Organization.find_by_domain(domain)

    if existing_org
    	return existing_org
    else
    	new_org.save
    	return new_org
    end
  end
end
