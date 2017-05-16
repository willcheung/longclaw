class ContextsmithService

  def self.load_emails_from_backend(project, max=100, query=nil, save_in_db=true, after=nil, is_time=true, neg_sentiment=0, request=true, is_test=false)
    base_url = ENV["csback_script_base_url"] + "/newsfeed/search"

    after = after.nil? ? "" : ("&after=" + after.to_s)
    query = query.nil? ? "" : ("&query=" + url_encode(query.to_s))
    is_time = is_time.nil? ? "" : ("&time=" + is_time.to_s)
    request = request.nil? ? "": ("&request=" + request.to_s)
    neg_sentiment = neg_sentiment.nil? ? "": ("&neg_sentiment=" + neg_sentiment.to_s)
    params = "&max=" + max.to_s + after + query + is_time + neg_sentiment + request

    #puts "~~~~~~ ContextsmithService will now call load_from_backend(). ~~~~~~"
    load_from_backend(project, base_url, params) do |data|
      puts "Found #{data[0]['conversations'].size} conversations!\n"
      Contact.load(data, project, save_in_db)
      # always load activity before notification
      result = Activity.load(data, project, save_in_db)
      Notification.load(data, project, is_test)
      result
    end
    #puts "~~~~~~ load_from_backend() processing exited! ~~~~~~"
  end
  
  # 6.months.ago or more is too long ago, returns nil. 150.days is just less than 6.months and should work.
  def self.load_calendar_from_backend(project, max=100, after=150.days.ago.to_i, before=1.5.days.from_now.to_i, save_in_db=true)
    base_url = ENV["csback_script_base_url"] + "/newsfeed/event"
    params =  "&max=" + max.to_s + "&before=" + before.to_s + "&after=" + after.to_s
    
    load_from_backend(project, base_url, params) do |data| 
      puts "Found #{data[0]['conversations'].size} calendar events!\n"
      Activity.load_calendar(data, project, save_in_db)
    end
  end

  def self.get_emails_from_backend_with_callback(user)
    max = ENV["max_emails"] ? ENV["max_emails"].to_i : 10000
    base_url = ENV["csback_base_url"] + "/newsfeed/cluster"
    callback_url = "#{ENV['BASE_URL']}/onboarding/#{user.id}/create_clusters.json"

    if Rails.env.production?
      sources = [{ token: user.fresh_token, email: user.email, kind: 'gmail' }]
      in_domain = ""
    elsif Rails.env.test? # Test / DEBUG 
      sources = [{ token: user.fresh_token, email: user.email, kind: 'gmail' }]
      in_domain = (user.email == 'indifferenzetester@gmail.com' ? "&in_domain=comprehend.com" : "")
    else # Dev environment
      u = User.find_by_email('indifferenzetester@gmail.com')
      sources = [{ token: u.fresh_token, email: u.email, kind: 'gmail' }]
      in_domain = "&in_domain=comprehend.com"
    end
    final_url = base_url + "?preview=true&time=true&neg_sentiment=0&cluster_method=BY_EMAIL_DOMAIN&max=" + max.to_s + "&callback=" + callback_url + in_domain
    puts "Calling backend service for clustering: " + final_url

    uri = URI(final_url)
    req = Net::HTTP::Post.new(uri, 'Content-Type' => 'application/json')
    req.body = { sources: sources }.to_json
    res = Net::HTTP.start(uri.host, uri.port) { |http| http.request(req) }
  end


  private

  def self.load_from_backend(project, base_url, params)
    #puts "********** We are in load_from_backend() ! ************"
    in_domain = Rails.env.development? ? "&in_domain=comprehend.com" : ""

    sources = []
    if Rails.env.development?
      sources << { token: "test", email: "indifferenzetester@gmail.com", kind: "gmail" }
    else
      project.users.registered.not_disabled.allow_refresh_inbox.each do |u|
        success = true
        success = u.refresh_token! if u.token_expired?
        sources << { token: u.oauth_access_token, email: u.email, kind: "gmail" } if success
      end
    end
    return [] if sources.empty?

    ex_clusters = [project.contacts.pluck(:email)]
       
    final_url = base_url + "?" + in_domain + params
    puts "Calling backend service: " + final_url

    begin
      uri = URI(final_url)
      req = Net::HTTP::Post.new(uri, 'Content-Type' => 'application/json')
      req.body = { sources: sources, external_clusters: ex_clusters }.to_json
      res = Net::HTTP.start(uri.host, uri.port 
        #, use_ssl: uri.scheme == "https"
        ) { |http| http.request(req) }
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
