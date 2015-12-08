# == Schema Information
#
# Table name: messages
#
#  id               :integer          not null, primary key
#  mime_message_id  :string           not null
#  gmail_message_id :string           not null
#  conversation_id  :integer
#  subject          :string           not null
#  sent_date_epoch  :string           not null
#  sent_date        :datetime         not null
#  preview_content  :text
#  to               :text             not null
#  from             :text             not null
#  cc               :text             default(""), not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#

class Message < ActiveRecord::Base
	belongs_to :conversation
end
