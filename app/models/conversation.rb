# == Schema Information
#
# Table name: conversations
#
#  id                   :integer          not null, primary key
#  backend_id           :string           not null
#  project_id           :integer
#  subject              :string           not null
#  last_sent_date       :datetime         not null
#  last_sent_date_epoch :string           not null
#  external_members     :text             not null
#  internal_members     :text             not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#

class Conversation < ActiveRecord::Base
	has_many :messages
	belongs_to :project
end
