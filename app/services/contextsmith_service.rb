require "erb"
include ERB::Util

class ContextsmithService

  def self.load_emails_from_backend(project, max=100, query=nil, save_in_db=true, after=nil, is_time=true, neg_sentiment=0, request=true, is_test=false)
    base_url = ENV["csback_script_base_url"] + "/newsfeed/search"

    after = after.nil? ? "" : ("&after=" + after.to_s)
    query = query.nil? ? "" : ("&query=" + url_encode(query.to_s))
    is_time = is_time.nil? ? "" : ("&time=" + is_time.to_s)
    request = request.nil? ? "": ("&request=" + request.to_s)
    neg_sentiment = neg_sentiment.nil? ? "": ("&neg_sentiment=" + neg_sentiment.to_s)
    params = "&max=" + max.to_s + after + query + is_time + neg_sentiment + request

    load_from_backend(project, base_url, params) do |data|
      puts "Found #{data[0]['conversations'].size} conversations!\n"
      Contact.load(data, project, save_in_db)
      # always load activity before notification
      result = Activity.load(data, project, save_in_db)
      Notification.load(data, project, is_test)
      result
    end
  end
  
  # 6.months.ago or more is too long ago, returns nil. 150.days is just less than 6.months and should work.
  def self.load_calendar_from_backend(project, max=100, after=150.days.ago.to_i, before=Time.current.to_i, save_in_db=true)
    base_url = ENV["csback_script_base_url"] + "/newsfeed/event"
    params =  "&max=" + max.to_s + "&before=" + before.to_s + "&after=" + after.to_s
    
    load_from_backend(project, base_url, params) do |data| 
      puts "Found #{data[0]['conversations'].size} calendar events!\n"
      Activity.load_calendar(data, project, save_in_db)
    end
  end

  def self.get_emails_from_backend_with_callback(user)
    max=10000
    base_url = ENV["csback_base_url"] + "/newsfeed/cluster"

    if Rails.env.production?
      callback_url = "#{ENV['BASE_URL']}/onboarding/#{user.id}/create_clusters.json"
      user.refresh_token! if user.token_expired?
      token_emails = [{ token: user.oauth_access_token, email: user.email }]
      in_domain = ""
    elsif Rails.env.test? # DEBUG
      max=888 #temp
      callback_url = "#{ENV['BASE_URL']}/onboarding/#{user.id}/create_clusters.json"
      user.refresh_token! if user.token_expired?
      token_emails = [{ token: user.oauth_access_token, email: user.email }]
      in_domain = (user.email == 'indifferenzetester@gmail.com' ? "&in_domain=comprehend.com" : "")
    else # Dev environment
      callback_url = "http://localhost:3000/onboarding/#{user.id}/create_clusters.json"
      u = User.find_by_email('indifferenzetester@gmail.com')
      u.refresh_token! if u.token_expired?
      token_emails = [{ token: u.oauth_access_token, email: u.email }]
      in_domain = "&in_domain=comprehend.com"
    end
    ### TODO: add "&request=true" to final_url
    final_url = base_url + "?token_emails=" + token_emails.to_json + "&preview=true&time=true&neg_sentiment=0&max=" + max.to_s + "&cluster_method=BY_EMAIL_DOMAIN&callback=" + callback_url + in_domain
    puts "Calling backend service for clustering: " + final_url
    puts "Callback URL set as: " + callback_url

    url = URI.parse(final_url)
    req = Net::HTTP::Get.new(url.to_s)
    res = Net::HTTP.start(url.host, url.port) { |http| http.request(req) }
  end


  private

  def self.load_from_backend(project, base_url, params)
    in_domain = Rails.env.development? ? "&in_domain=comprehend.com" : ""

    token_emails = []
    if Rails.env.development?
      token_emails << { token: "test", email: "indifferenzetester@gmail.com" }
    else
      project.users.registered.not_disabled.each do |u|
        success = true
        success = u.refresh_token! if u.token_expired?
        token_emails << { token: u.oauth_access_token, email: u.email } if success
      end
    end
    return [] if token_emails.empty?

    ex_clusters = project.contacts.pluck(:email)
    
    new_ex_clusters = Hash.new { |h,k| h[k] = [] }
    ex_clusters.each do |e|
      result = e.split('@')
      new_ex_clusters[result[1]] << result[0]
    end

    final_cluster = []
    new_ex_clusters.each do |key, value|
      final_cluster.push(value.join('|') + "@"+ key)
    end
       
    final_url = base_url + "?token_emails=" + token_emails.to_json + "&ex_clusters=" + url_encode([final_cluster].to_s) + in_domain + params
    puts "Calling backend service: " + final_url

    begin
      url = URI.parse(final_url)
      req = Net::HTTP::Get.new(url.to_s)
      res = Net::HTTP.start(url.host, url.port) { |http| http.request(req) }
      data = JSON.parse(res.body.to_s)
    rescue => e
      puts "ERROR: Something went wrong: " + e.message
      puts e.backtrace.join("\n")
    end

    if data.nil? or data.empty?
      puts "No data or nil returned!\n"
      return []
    elsif data.kind_of?(Array)
      yield data
    elsif data['code'] == 401
      puts "Error: #{data['message']}\n"
      return []
    elsif data['code'] == 404
      puts "#{data['message']}\n"
      return []
    else
      puts "Unhandled backend response."
      return []
    end
  end
end
