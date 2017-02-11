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
      SELECT projects.name AS context_project_name, activities.title AS basecamp_project_name ,integrations.id AS int_id
			FROM integrations
				LEFT JOIN activities ON integrations.external_account_id = activities.backend_id
				LEFT JOIN projects ON integrations.project_id = projects.id
				WHERE contextsmith_account_id IS NOT NULL;
      SQL
    result = Project.find_by_sql(query)
  end

  





end
