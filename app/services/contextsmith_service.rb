require "erb"
include ERB::Util

class ContextsmithService

  def self.load_emails_from_backend(project, after=nil, max=100, query=nil, save_in_db=true, is_time=true, is_test=false, neg_sentiment=0)
    base_url = ENV["csback_script_base_url"] + "/newsfeed/search"
    
    in_domain = Rails.env.development? ? "&in_domain=comprehend.com" : ""
    token_emails = get_token_emails
    return [] if token_emails.empty?

    if ENV["RAILS_ENV"] == 'production' or ENV["RAILS_ENV"] == 'test'
      in_domain = ""
      project.users.registered.not_disabled.each do |u|
        success = true
        if u.token_expired?
          success = u.refresh_token!
        end
        token_emails << { token: u.oauth_access_token, email: u.email } if success
      end
      return [] if token_emails.empty?
    else
      # DEBUG
      u = User.find_by_email('indifferenzetester@gmail.com')
      # u.refresh_token! if u.token_expired?
      token_emails << { token: "test", email: u.email }
      in_domain = "&in_domain=comprehend.com"
    end

    ex_clusters = [project.contacts.map(&:email)]

    # change ex_clusters to abc|def@domain.com format
    new_ex_clusters = Hash.new()
    ex_clusters[0].each do |e|
      result = e.split('@')
      # avoid ruby 2.2.3 hash bug
      if !new_ex_clusters.has_key?(result[1])
        new_ex_clusters[result[1]] = []   
      end  
      new_ex_clusters[result[1]] << result[0]
    end
 
    final_cluster = []
    new_ex_clusters.each do |key, value|
      final_cluster.push(value.join('|') + "@"+key.to_s)
    end

    after = after.nil? ? "" : ("&after=" + after.to_s)
    query = query.nil? ? "" : ("&query=" + query.to_s)
    is_time = is_time.nil? ? "": ("&time=" + is_time.to_s)
    neg_sentiment = neg_sentiment.nil? ? "": ("&neg_sentiment=" + neg_sentiment.to_s)
       
    final_url = base_url + "?token_emails=" + token_emails.to_json + "&max=" + max.to_s + "&ex_clusters=" + url_encode([final_cluster].to_s) + in_domain + after + url_encode(query) + is_time + neg_sentiment
    puts "Calling backend service: " + final_url

    request_backend_service(final_url, project, save_in_db, "conversations")    
  end

  
  def self.load_calendar_from_backend(project, before, after, max=100, save_in_db=true)
    base_url = ENV["csback_script_base_url"] + "/newsfeed/event"
    
    in_domain = Rails.env.development? ? "&in_domain=comprehend.com" : ""
    token_emails = get_token_emails
    return [] if token_emails.empty?
    ###
    # TESTING USING REAL TOKENS DUE TO PERMISSIONS
    ###
    if Rails.env.development?
      u = User.find_by_email("indifferenzetester@gmail.com")
      success = true
      if u.token_expired?
        success = u.refresh_token!
      end
      token_emails = []
      token_emails << { token: u.oauth_access_token, email: u.email } if success
      return [] if token_emails.empty?
    end
    ###
    # TESTING USING ANY EMAIL OTHER THAN TEST ACCOUNT EMAIL FOR EXTERNAL CLUSTER
    ###
    # ex_clusters = (project.users + project.contacts).select { |c| c.email != 'indifferenzetester@gmail.com' }.map(&:email)
    ex_clusters = project.contacts.map(&:email)
    final_cluster = format_ex_clusters(ex_clusters)
       
    final_url = base_url + "?token_emails=" + token_emails.to_json + "&max=" + max.to_s + "&ex_clusters=" + url_encode([final_cluster].to_s) + in_domain + "&before=" + before.to_s + "&after=" + after.to_s
    puts "Calling backend service: " + final_url
    
    request_backend_service(final_url, project, save_in_db, "events")
  end

  private
  def self.get_token_emails
    token_emails = []
    if Rails.env.production? || Rails.env.test?
      project.users.registered.not_disabled.each do |u|
        success = true
        if u.token_expired?
          success = u.refresh_token!
        end
        token_emails << { token: u.oauth_access_token, email: u.email } if success
      end
    else
      u = User.find_by_email('indifferenzetester@gmail.com')
      token_emails << { token: "test", email: u.email }
    end
    token_emails
  end

  # change ex_clusters to abc|def@domain.com format
  def self.format_ex_clusters(ex_clusters)
    new_ex_clusters = Hash.new()
    ex_clusters.each do |e|
      result = e.split('@')
      # avoid ruby 2.2.3 hash bug
      new_ex_clusters[result[1]] = [] unless new_ex_clusters.has_key?(result[1])
      new_ex_clusters[result[1]] << result[0]
    end

    final_cluster = []
    new_ex_clusters.each do |key, value|
      final_cluster.push(value.join('|') + "@"+ key)
    end
    final_cluster
  end

  def self.request_backend_service(url, project, save_in_db, type)
    begin
      url = URI.parse(url)
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
      puts "Found #{data[0]['conversations'].size} #{type}!\n"
      if type == "conversations"
        Contact.load(data, project, save_in_db)
        Notification.load(data, project, is_test)
        return Activity.load(data, project, save_in_db)
      elsif type == "events"
        return Activity.load_calendar(data, project, save_in_db)
      end
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