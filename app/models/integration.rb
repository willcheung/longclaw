# == Schema Information
#
# Table name: integrations
#
#  id                      :integer          not null, primary key
#  contextsmith_account_id :uuid
#  external_account_id     :string
#  project_id              :uuid
#  external_source         :string
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#

class Integration < ActiveRecord::Base
	belongs_to  :organization, foreign_key: "contextsmith_organization_id"
	belongs_to :oauth_user
	belongs_to :users

	def self.link_basecamp2(basecamp_account_id, account_id, external_name, current_user, project_id)

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


	 def self.find_basecamp_connections
    query = <<-SQL
       SELECT integrations.contextsmith_account_id AS project_id,
       		  projects.name AS context_project_name,
       		  integrations.external_source AS basecamp_project_name,
       		  integrations.id AS int_id,
       		  integrations.external_account_id AS basecamp_project_id
			FROM integrations
				LEFT JOIN projects ON integrations.contextsmith_account_id = projects.id
				;
      SQL
    result = Project.find_by_sql(query)
  end

  





end
