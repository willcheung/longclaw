# == Schema Information
#
# Table name: company_profiles
#
#  id         :integer          not null, primary key
#  domain     :string           default(""), not null
#  expires_at :datetime
#  data       :jsonb
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes
#
#  index_company_profiles_on_domain  (domain)
#

class CompanyProfile < ActiveRecord::Base
  before_save :downcase_domain

  def self.find_or_create_by_domain(domain)
    company = find_by_domain(domain)
    company = create(domain: domain) if company.blank?
    if company.data.blank? || [200, 202, 404].exclude?(company.data.status)
      company.data = FullContactService.find_company(domain, company.id)
      company.save
    end
    company
  end

  # status is a top-level attribute of data, tells you whether data is there
  # data.status == 200: data has been pulled from FullContact
  # data.status == 202: webhook has been registered, data will be pulled from FullContact
  # data.status == 4xx: data could not be pulled from FullContact
  def data
    Hashie::Mash.new(read_attribute(:data))
  end

  def data_is_valid?
    data.present? && data.status == 200
  end

  def name
    data.name if data_is_valid?
  end

  def location
    data.location if data_is_valid?
  end

  def bio
    data.bio if data_is_valid?
  end

  def employees
    data.employees if data_is_valid?
  end

  def date_founded
    data.founded if data_is_valid?
  end

  def key_people
    data.details.keyPeople if data_is_valid? && data.details?
  end

  def website
    data.website || (data.details.urls.first.value if data.details?) if data_is_valid?
  end

  def social_url(social_type)
    social_type = get_FullContact_social_profile_type(social_type)
    data.send(social_type) if data_is_valid?
    # sp = data.social_profiles.find{ |sp| sp.type_id.downcase == social_type } if social_type.present? && data_is_valid? && data.social_profiles.present?
    # URI.encode(sp.url) if sp.present? && sp.url.present?
  end

  def social_bio(social_type)
    social_type = get_FullContact_social_profile_type(social_type, true)
    if data_is_valid?
      social_profile = data.details.profiles.send(social_type)
      social_profile.bio if social_profile
    end
  end

  private

  def get_FullContact_social_profile_type(cs_social_type, bio=false)
    case cs_social_type
      when Profile::SOCIAL_TYPE[:Linkedin]
        return bio ? :linkedincompany : :linkedin
      when Profile::SOCIAL_TYPE[:Twitter]
        return :twitter
      when Profile::SOCIAL_TYPE[:Facebook]
        return :facebook
    end
  end

  def downcase_domain
    self.domain.downcase!
  end
end
