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
  before_save :downcase_emails

  scope :where_by_email, -> (email) { where('emails @> ?', '{' + email.downcase + '}') }

  SOCIAL_TYPE = { Linkedin: 'LinkedIn', Twitter: 'Twitter', Facebook: 'Facebook' }

  def self.find_by_email(email)
    begin
      where_by_email(email).first
    rescue => e
      puts "**** Error while running Profile.find_by_email(#{email}):\nException: #{e.to_s}\n****"
    end
  end

  ### finds or creates a Profile and tries to populate it with data from FullContact
  # Example return values:
  # #<Profile id: 13, emails: ["invalid@not-real.com"], expires_at: nil, data: {"status"=>404, "exception"=>{"http_headers"=>{"date"=>"Thu, 31 Aug 2017 19:00:52 GMT", "server"=>"nginx", "connection"=>"close", "content-type"=>"application/json;charset=UTF-8", "content-length"=>"154", "x-rate-limit-limit"=>"60", "x-rate-limit-reset"=>"60", "x-rate-limit-remaining"=>"59", "strict-transport-security"=>"max-age=86400"}}}, created_at: "2017-08-31 19:00:52", updated_at: "2017-08-31 19:00:52">
  # #<Profile id: 10, emails: ["wcheung@contextsmith.com"], expires_at: nil, data: {"photos"=>[{"url"=>"https://d2ojpxxtu63wzl.cloudfront.net/static/d0f562affca25168bffc4fb0bf9166a8_aa5d575cc9ebf8b7f9dd42cd357cc55f3c2a82e24aa2c3683c67570ab2812553", "type"=>"linkedin", "type_id"=>"linkedin", "type_name"=>"LinkedIn", "is_primary"=>true}, {"url"=>"https://d2ojpxxtu63wzl.cloudfront.net/static/e3b0148f5dca71a99723e2711dbc2c92_b0cfd2d3917492e7f0d60ebca67e65b37c7ba519d939f8dae9ebb6eec8910ff4", "type"=>"facebook", "type_id"=>"facebook", "type_name"=>"Facebook"}, {"url"=>"https://d2ojpxxtu63wzl.cloudfront.net/static/a16e14e3efb4e7ef542750c5d3edb184_3f81684814c9f9f9e4802971a3909f90b7ee331fb94b4dfa6b1cc4bec9fb49a5", "type"=>"gravatar", "type_id"=>"gravatar", "type_name"=>"Gravatar"}, {"url"=>"https://d2ojpxxtu63wzl.cloudfront.net/static/66259f617f379ef925ca86c7fb8fbbe3_c274c655a6439630f79acc74272d113273ab772e6c5ff02380f91b9ddcc07bd3", "type"=>"foursquare", "type_id"=>"foursquare", "type_name"=>"Foursquare"}, {"url"=>"https://d2ojpxxtu63wzl.cloudfront.net/static/0ba9fb7811b7d63a235c648cf2f77a91_8062996b9a73304307a8579a5fd564005ef265800310191265d7a61004b037fb", "type"=>"angellist", "type_id"=>"angellist", "type_name"=>"AngelList"}, {"url"=>"https://d2ojpxxtu63wzl.cloudfront.net/static/9c669a39099e0dda300cac84bd6caffa_e2572f42fe997b2202dee861cffb42066ca9d3cecaab8d7d764111d65654a259", "type"=>"twitter", "type_id"=>"twitter", "type_name"=>"Twitter"}, {"url"=>"https://d2ojpxxtu63wzl.cloudfront.net/static/a0cadb312019064bc93eb780ac49ea6e_6b9fb04065f75f12b4e3825a6276a939f031d6a9109184af632f1b812efe0cb3", "type"=>"pinterest", "type_id"=>"pinterest", "type_name"=>"Pinterest"}], "status"=>200, "likelihood"=>0.95, "request_id"=>"52ce8a22-79e5-47d1-8162-dfc5dc5380ee", "contact_info"=>{"websites"=>[{"url"=>"http://www.contextsmith.com"}], "full_name"=>"Will Cheung", "given_name"=>"Will", "family_name"=>"Cheung"}, "demographics"=>{"gender"=>"Male", "location_deduced"=>{"city"=>{"name"=>"Palo Alto"}, "state"=>{"code"=>"CA", "name"=>"California"}, "county"=>{"name"=>"Santa Clara", "deduced"=>true}, "country"=>{"code"=>"US", "name"=>"United States"}, "continent"=>{"name"=>"North America", "deduced"=>true}, "likelihood"=>1.0, "deduced_location"=>"Palo Alto, California, United States", "normalized_location"=>"Palo Alto, California, United States"}, "location_general"=>"Palo Alto, California, United States"}, "organizations"=>[{"name"=>"ContextSmith", "title"=>"Founder & CEO", "current"=>true, "start_date"=>"2016"}, {"name"=>"Comprehend", "title"=>"Director of Customer Solution", "current"=>true, "start_date"=>"2012"}, {"name"=>"Facebook", "title"=>"BI Lead - Open Graph", "end_date"=>"2012", "start_date"=>"2012"}, {"name"=>"Netflix", "title"=>"Manager - A/B Analytics", "end_date"=>"2012", "start_date"=>"2011"}, {"name"=>"DuffelUp.com", "title"=>"Founder & Product Guy", "end_date"=>"2011", "start_date"=>"2009"}], "social_profiles"=>[{"id"=>"13406", "bio"=>"Exec @comprehend, BI leader @netflix  @blackhawk-network, Founder @duffel-1 • Expert in enterprise SaaS; passionate about building great teams and products", "url"=>"https://angel.co/willcheung", "type"=>"angellist", "type_id"=>"angellist", "username"=>"willcheung", "followers"=>175, "type_name"=>"AngelList"}, {"url"=>"https://www.facebook.com/willcheung", "type"=>"facebook", "type_id"=>"facebook", "type_name"=>"Facebook"}, {"id"=>"54848397@N00", "url"=>"https://www.flickr.com/people/54848397@N00", "type"=>"flickr", "type_id"=>"flickr", "username"=>"indifferenze", "type_name"=>"Flickr"}, {"id"=>"302678", "url"=>"https://foursquare.com/user/302678", "type"=>"foursquare", "type_id"=>"foursquare", "type_name"=>"Foursquare"}, {"id"=>"106019053614327464096", "bio"=>"Loves to travel and sample ethnic cuisine.", "url"=>"https://plus.google.com/106019053614327464096", "type"=>"google", "type_id"=>"google", "username"=>"willy.cheung", "followers"=>190, "type_name"=>"GooglePlus"}, {"id"=>"456770", "url"=>"https://gravatar.com/willcheung", "type"=>"gravatar", "type_id"=>"gravatar", "username"=>"willcheung", "type_name"=>"Gravatar"}, {"url"=>"https://instagram.com/willcheung", "type"=>"instagram", "type_id"=>"instagram", "type_name"=>"Instagram"}, {"id"=>"37436176667254379", "url"=>"http://klout.com/willcheung", "type"=>"klout", "type_id"=>"klout", "username"=>"willcheung", "type_name"=>"Klout"}, {"id"=>"5089884", "bio"=>"Data-driven leader with 14+ years of experience in building high-performance products and teams. Served leadership roles in various teams like Data Engineering, BI, Product, Customer Success, and Sales at startups and top-tier tech companies. Specializes in leading enterprise solutions projects, deployment, customer onboarding, and adoption.", "url"=>"https://www.linkedin.com/in/willcheung", "type"=>"linkedin", "type_id"=>"linkedin", "username"=>"willcheung", "followers"=>500, "following"=>500, "type_name"=>"LinkedIn"}, {"url"=>"http://www.pinterest.com/willcheung/", "type"=>"pinterest", "type_id"=>"pinterest", "username"=>"willcheung", "followers"=>115, "following"=>22, "type_name"=>"Pinterest"}, {"id"=>"10168152", "bio"=>"Analytics / data guy, entrepreneur, and food lover", "url"=>"https://twitter.com/willcheung", "type"=>"twitter", "type_id"=>"twitter", "username"=>"willcheung", "followers"=>143, "following"=>131, "type_name"=>"Twitter"}], "digital_footprint"=>{"scores"=>[{"type"=>"general", "value"=>30, "provider"=>"klout"}], "topics"=>[{"value"=>"Analytics & Reporting", "provider"=>"angellist"}, {"value"=>"Business Intelligence", "provider"=>"angellist"}, {"value"=>"Customer Success", "provider"=>"angellist"}, {"value"=>"Enterprise Software", "provider"=>"angellist"}, {"value"=>"Hacker", "provider"=>"angellist"}, {"value"=>"Product Management", "provider"=>"angellist"}, {"value"=>"Professional Services", "provider"=>"angellist"}, {"value"=>"SaaS", "provider"=>"angellist"}, {"value"=>"Business Development", "provider"=>"klout"}, {"value"=>"CEOs and Executives", "provider"=>"klout"}, {"value"=>"Y Combinator", "provider"=>"klout"}]}}, created_at: "2017-08-31 01:56:11", updated_at: "2017-08-31 01:56:11">
  # #<Profile id: 15, emails: ["test5@contextsmith.com"], expires_at: nil, data: {"status"=>202, "message"=>"Queued for search. Please retry your query within about 2 minutes. Prefer not to re-submit queries? Try using our webhook option, documented at: http://www.fullcontact.com/developer/docs/person/#webhook-email", "request_id"=>"df105112-0cb7-4fa7-872b-f4687224f32c"}, created_at: "2017-08-31 19:27:54", updated_at: "2017-08-31 19:27:55">
  def self.find_or_create_by_email(email)
    profile = find_by_email(email)
    # No existing profile found, create a new one
    profile = Profile.create(emails: [email]) if profile.blank?
    if profile.data.blank?
      profile.data = FullContactService.find(email, profile.id)
      profile.save
    end
    profile
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

  # "First name"
  def given_name
    data.contact_info.given_name if data_is_valid? && data.contact_info.present?
  end

  # "Last name"
  def family_name
    data.contact_info.family_name if data_is_valid? && data.contact_info.present?
  end

  def fullname
    data.contact_info.full_name if data_is_valid? && data.contact_info.present?
  end

  def email
    self.emails.first
  end

  def title
    data.organizations.first.title if data_is_valid? && data.organizations.present?
  end

  def organization
    data.organizations.first.name if data_is_valid? && data.organizations.present?
  end

  def profileimg_url
    URI.encode(data.photos.first.url) if data_is_valid? && data.photos.present?
  end

  def social_url(socialtype)
    socialtype = get_FullContact_social_profile_type(socialtype)
    sp = data.social_profiles.find{ |sp| sp.type_id.downcase == socialtype } if socialtype.present? && data_is_valid? && data.social_profiles.present?
    URI.encode(sp.url) if sp.present? && sp.url.present?
  end

  # Returns an array of [website, website's subdomain/domain "short" name] associated with this profile
  def websites
    if data_is_valid? && data.contact_info.present? && data.contact_info.websites.present?
      return  data.contact_info.websites.map do |w| 
                begin
                  [URI.encode(w.url), URI.parse(w.url).host.sub(/^www\./, '')]
                rescue Exception => e
                  [URI.encode(w.url), w.url]
                end
              end
    end
    []
  end

  def location
    data.demographics.location_general || (data.demographics.location_deduced.present? && (data.demographics.location_deduced.normalized_location || data.demographics.location_deduced.deduced_location)) if (data_is_valid? && data.demographics.present?)
  end

  # TODO: temporary placeholder (might remove)
  def phone
    nil
  end

  def social_bio(socialtype)
    socialtype = get_FullContact_social_profile_type(socialtype)
    sp = p.data.social_profiles.find{ |sp| sp.type_id.present? ? sp.type_id.downcase == socialtype : (sp.type.downcase == socialtype if sp.type.present?) } if socialtype.present? && data_is_valid? && data.social_profiles.present?
    sp.bio if sp.present?
  end

  private

  def get_FullContact_social_profile_type(cs_social_type)
    case cs_social_type
    when SOCIAL_TYPE[:Linkedin]
      return "linkedin"
    when SOCIAL_TYPE[:Twitter]
      return "twitter"
    when SOCIAL_TYPE[:Facebook]
      return "facebook"
    end
  end

  def downcase_emails
    self.emails.map!(&:downcase)
  end

end
