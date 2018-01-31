# == Schema Information
#
# Table name: notes
#
#  id            :integer          not null, primary key
#  title         :string(50)       default("")
#  note          :text             not null
#  noteable_type :string           not null
#  noteable_uuid :uuid             not null
#  user_uuid     :uuid             not null
#  is_public     :boolean          default(FALSE)
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#
# Indexes
#
#  index_notes_on_noteable_type  (noteable_type)
#  index_notes_on_noteable_uuid  (noteable_uuid)
#  index_notes_on_user_uuid      (user_uuid)
#

class Note < ActiveRecord::Base
  belongs_to :noteable, polymorphic: true, foreign_key: "noteable_uuid"

  default_scope -> { order('created_at ASC') }

  belongs_to :user, foreign_key: "user_uuid"
end
