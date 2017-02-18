# == Schema Information
#
# Table name: custom_lists
#
#  id                       :integer          not null, primary key
#  custom_lists_metadata_id :integer          not null
#  option_value             :string           not null
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#
# Indexes
#
#  index_custom_lists_on_custom_lists_metadata_id  (custom_lists_metadata_id)
#

class CustomList < ActiveRecord::Base
	belongs_to :custom_lists_metadatum, foreign_key: "custom_lists_metadata_id"
	
	validates :custom_lists_metadatum, presence: true
end
