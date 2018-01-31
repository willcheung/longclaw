
class FullContactService

  # # # Uses FullContact gem, which makes requests with FullContact API v2
  # Call the FullContact Person API to find a person by email and returns the response
  # if data not found in FullContact's cache, another call is made to register a webhook so an update is pushed to us when data is available
  def self.find_person(email, profile_id)
    res = FullContact.person(email: email)
    # not found in FullContact cache, register a webhoook to send the info back to us when it is available
    FullContact.person(email: email, webhookUrl: ENV['BASE_URL'] + '/hooks/fullcontact_person', webhookBody: 'json', webhookId: { email: email, id: profile_id }.to_json) if res.blank? || res.status == 202
    res
  rescue => e
    puts "Request to FullContact v2 Person API FAILED: #{e.inspect}"
    { status: e.to_s[-3..-1].to_i, exception: e }
  end

  # # # Uses FullContact gem, which makes requests with FullContact API v2
  # Call the FullContact Company API to find a company by domain and returns the response
  # if data not found in FullContact's cache, another call is made to register a webhook so an update is pushed to us when data is available
  def self.find_company_v2(domain, company_profile_id)
    res = FullContact.company(domain: domain)
    # not found in FullContact cache, register a webhoook to send the info back to us when it is available
    FullContact.company(domain: domain, webhookUrl: ENV['BASE_URL'] + '/hooks/fullcontact_company', webhookBody: 'json', webhookId: { domain: domain, id: company_profile_id }.to_json) if res.blank? || res.status == 202
    res
  rescue => e
    puts "Request to FullContact v2 Company API FAILED: #{e.inspect}"
    { status: e.to_s[-3..-1].to_i, exception: e }
  end

  # # # Uses raw HTTP requests to call FullContact API v3
  # Call the FullContact Enrich (Company) API to find a company by domain and returns the response
  # if data not found in FullContact's cache, another call is made to register a webhook so an update is pushed to us when data is available
  def self.find_company_v3(domain, company_profile_id)
    url = 'https://api.fullcontact.com/v3/company.enrich'
    uri = URI(url)
    req = Net::HTTP::Post.new(uri, 'Authorization' => "Bearer #{ENV['fullcontact_api_key']}")
    req.body = { domain: domain }.to_json
    res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") { |http| http.request(req) }


    # not found in FullContact cache, register a webhoook to send the info back to us when it is available
    unless [200, 404].include?(res.code.to_i)
      req.body = { domain: domain, webhookUrl: ENV['BASE_URL'] + '/hooks/fullcontact_company?' + { domain: domain, id: company_profile_id }.to_param }.to_json
      # req.body = { domain: domain, webhookUrl: 'https://requestb.in/1i5hd801?' + { domain: domain, id: company_profile_id }.to_param }.to_json
      res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") { |http| http.request(req) }
    end
    response = JSON.parse(res.body)
    response['status'] = res.code.to_i
    response
  rescue => e
    puts "Request to FullContact v3 Enrich (Company) API FAILED: #{e.inspect}"
    { status: e.to_s[-3..-1].to_i, exception: e }
  end

  # # # TODO: DELETE THIS ONCE API VERSION IS DECIDED
  # Temporary alias for find_company while deciding whether to use v2 or v3 of Company API
  singleton_class.send(:alias_method, :find_company, :find_company_v3)
end