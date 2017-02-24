# == Schema Information
#
# Table name: custom_lists_metadata
#
#  id              :integer          not null, primary key
#  organization_id :uuid             not null
#  name            :string           not null
#  cs_app_list     :boolean          default(FALSE), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#
# Indexes
#
#  index_custom_lists_metadata_on_organization_id_and_name  (organization_id,name)
#

class CustomListsMetadatum < ActiveRecord::Base
	belongs_to :organization
	has_many :custom_lists, foreign_key: "custom_lists_metadata_id", dependent: :destroy
	has_many :custom_fields, class_name: "CustomFieldsMetadatum", foreign_key: "custom_lists_metadata_id", dependent: :nullify
	
	validates :name, presence: true, length: { maximum: 30 }

	# Create default application Custom Lists for a new organization
	def self.create_default_for(organization)
		clm1 = create(organization: organization, name:"Account Type", cs_app_list: true)
		clm1.custom_lists.create(option_value: "Competitor")
		clm1.custom_lists.create(option_value: "Customer")
		clm1.custom_lists.create(option_value: "Investor")
		clm1.custom_lists.create(option_value: "Integrator")
		clm1.custom_lists.create(option_value: "Partner")
		clm1.custom_lists.create(option_value: "Press")
		clm1.custom_lists.create(option_value: "Prospect")
		clm1.custom_lists.create(option_value: "Reseller")
		clm1.custom_lists.create(option_value: "Vendor")
		clm1.custom_lists.create(option_value: "Other")
		clm2 = create(organization: organization, name:"Stream Type", cs_app_list: true)
		clm2.custom_lists.create(option_value: "Adoption")
		clm2.custom_lists.create(option_value: "Expansion")
		clm2.custom_lists.create(option_value: "Implementation")
		clm2.custom_lists.create(option_value: "Onboarding")
		clm2.custom_lists.create(option_value: "Opportunity")
		clm2.custom_lists.create(option_value: "Pilot")
		clm2.custom_lists.create(option_value: "Support")
		clm2.custom_lists.create(option_value: "Other")
		clm3 = create(organization: organization, name:"Region")
		clm3.custom_lists.create(option_value: "East")
		clm3.custom_lists.create(option_value: "Mid-Atlantic")
		clm3.custom_lists.create(option_value: "North")
		clm3.custom_lists.create(option_value: "Northeast")
		clm3.custom_lists.create(option_value: "Northwest")
		clm3.custom_lists.create(option_value: "Midwest")
		clm3.custom_lists.create(option_value: "South")
		clm3.custom_lists.create(option_value: "Southeast")
		clm3.custom_lists.create(option_value: "Southwest")
		clm3.custom_lists.create(option_value: "West")
		clm3.custom_lists.create(option_value: "Africa")
		clm3.custom_lists.create(option_value: "North America")
		clm3.custom_lists.create(option_value: "South America")
		clm3.custom_lists.create(option_value: "Asia")
		clm3.custom_lists.create(option_value: "EMEA")
		clm3.custom_lists.create(option_value: "Europe")
		clm3.custom_lists.create(option_value: "Oceania")
	end

	# Get (a preview of) options for this Custom List as a string. If no options exist, returns "(No options)". Use the optional list_strlen_limit parameter to truncate and limit the length of the string (length = the options portion, square brackets and ellipsis excluded) returned; the string with have ellipsis (...) appended if it has been truncated.
	def get_list_options(list_strlen_limit=nil)
		values = ""
		self.custom_lists.each { |l| values += l.option_value + ", " }
		values = values[0, values.length-2] # be sure to remove extra trailing comma+sp
		return "(No options)" if values.nil?

		if list_strlen_limit && list_strlen_limit < values.length
			"[" + values[0, list_strlen_limit.to_i] + "...]"
		else
			"[" + values + "]"
		end
	end
end
