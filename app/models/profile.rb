# == Schema Information
#
# Table name: profiles
#
#  id         :integer          not null, primary key
#  emails     :text             default([]), is an Array
#  expires_at :datetime
#  data       :jsonb
#  created_at :datetime         not null
#  updated_at :datetime         not null
#

class Profile < ActiveRecord::Base

  scope :where_by_email, -> (email) { where('emails @> ?', '{' + email + '}') }

  def self.find_by_email(email)
    where_by_email(email).first
  end

  def self.find_with_info_by_email(email)
    profile = find_by_email(email)
    if profile.blank?
      # No existing profile found, create a new one
      profile = Profile.create(emails: [email])
      profile.data = FullContactService.find(email, profile.id)
      profile.save
    end
    profile
  end

  def data
    Hashie::Mash.new(read_attribute(:data))
  end

end
