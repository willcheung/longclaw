require "erb"
include ERB::Util

class ContextsmithService

  def self.load_emails_from_backend(project, after=nil, max=100, query=nil, save_in_db=true, is_time=true, is_test=false, neg_sentiment=0)
    token_emails = []
    base_url = ENV["csback_script_base_url"] + "/newsfeed/search"

    # if ENV["RAILS_ENV"] == 'production' or ENV["RAILS_ENV"] == 'test' or ENV["RAILS_ENV"] == 'development'
    if true
      in_domain = ""
      project.users.registered.not_disabled.each do |u|
        puts "**********************woof*********************"
        success = true
        # if u.token_expired?
        if true
          success = u.refresh_token!
        end
        token_emails << { token: u.oauth_access_token, email: u.email } if success
      end
      puts "=========meow============"
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
    
    begin
      url = URI.parse(final_url)
      req = Net::HTTP::Get.new(url.to_s)
      res = Net::HTTP.start(url.host, url.port) { |http| http.request(req) }
      if res.code.to_s == '200'  #HTTP request ok
        data = JSON.parse(res.body.to_s)
      else
        puts "HTTP request error: " + res.code.to_s
      end
    rescue => e
      puts "ERROR: Something went wrong: " + e.message
      puts e.backtrace.join("\n")
    end

    if data.nil? or data.empty?
      puts "No data or nil returned!\n"
      return []
    elsif data.kind_of?(Array)
      puts "Found #{data[0]['conversations'].size} conversations!\n"
      Contact.load(data, project, save_in_db)
      Notification.load(data, project, is_test)
      return Activity.load(data, project, save_in_db)
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
  
  def self.load_calendar_from_backend(project, before, after, max=100, save_in_db=true)
    token_emails = []
    # TODO get the url for API calls
    base_url = ENV["csback_script_base_url"] + "/newsfeed/event"

    if Rails.env.production? || Rails.env.test?
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
      # u = User.find_by_email('indifferenzetester@gmail.com')
      token_emails << { token: "test", email: "indifferenzetester@gmail.com" }
      in_domain = "&in_domain=comprehend.com"
    end

    ex_clusters = project.contacts.map(&:email)

    # change ex_clusters to abc|def@domain.com format
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
       
    final_url = base_url + "?token_emails=" + token_emails.to_json + "&max=" + max.to_s + "&ex_clusters=" + url_encode([final_cluster].to_s) + in_domain + "&before=" + before.to_s + "&after=" + after.to_s
    puts "Calling backend service: " + final_url
    
    begin
      url = URI.parse(final_url)
      req = Net::HTTP::Get.new(url.to_s)
      res = Net::HTTP.start(url.host, url.port) { |http| http.request(req) }
      # if res.code.to_s == '200'  #HTTP request ok
        data = JSON.parse(res.body.to_s)
      # else
        # puts "HTTP request error: " + res.code.to_s
      # end
    rescue => e
      puts "ERROR: Something went wrong: " + e.message
      puts e.backtrace.join("\n")
    end

    if data.nil? || data.empty?
      puts "No data or nil returned!\n"
      return []
    elsif data.kind_of?(Array)
      puts "Found #{data[0]['events'].size} events!\n"
      return Activity.load_calendar(data, project, save_in_db)
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