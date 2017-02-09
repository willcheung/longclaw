# == Schema Information
#
# Table name: integrations
#
#  id                      :integer          not null, primary key
#  contextsmith_account_id :uuid
#  external_account_id     :integer
#  project_id              :uuid
#  external_source         :string
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#

class Integration < ActiveRecord::Base
	belongs_to :oauth_user

	def self.link_basecamp2(basecamp_account_id, account_id, external_name, current_user, project_id)
		puts "basecamp_account_id #{basecamp_account_id}"
		puts "account id #{account_id}"
		puts "external name #{external_name}"
		puts "current user #{current_user}"
		puts "project_id #{project_id}"

		tier = Integration.new(

				contextsmith_account_id: account_id,
				external_account_id: basecamp_account_id,
				project_id: project_id,
				external_source: external_name,
			)

		if tier.valid?
			tier.save
		end
	end





end
