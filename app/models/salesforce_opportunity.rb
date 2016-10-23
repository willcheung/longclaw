# == Schema Information
#
# Table name: salesforce_opportunities
#
#  id                        :integer          not null, primary key
#  salesforce_opportunity_id :string           default(""), not null
#  salesforce_account_id     :string           default(""), not null
#  name                      :string           default(""), not null
#  description               :text
#  amount                    :decimal(8, 2)
#  decimal                   :decimal(8, 2)
#  is_closed                 :boolean
#  is_won                    :boolean
#  stage_name                :string
#  renewal_date              :date
#  contract_start_date       :date
#  contract_end_date         :date
#  contract_arr              :decimal(8, 2)
#  contract_mrr              :decimal(8, 2)
#  custom_fields             :hstore
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#
# Indexes
#
#  index_salesforce_opportunities_on_custom_fields  (custom_fields)
#

class SalesforceOpportunity < ActiveRecord::Base
	belongs_to	:salesforce_account, foreign_key: "salesforce_account_id"
end
