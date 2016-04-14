require "erb"
include ERB::Util

class ContextsmithService

  def self.load_emails_from_backend(project, after=nil, max=100, query=nil, save_in_db=true, is_time=true, is_test=false)
    token_emails = []
    base_url = ENV["csback_script_base_url"] + "/newsfeed/search"

    if ENV["RAILS_ENV"] == 'production' or ENV["RAILS_ENV"] == 'test'
      in_domain = ""
      project.users.registered.each do |u|
        u.refresh_token! if u.token_expired?
        token_emails << { token: u.oauth_access_token, email: u.email }
      end
      return [] if token_emails.empty?
    else
      # DEBUG
      u = User.find_by_email('klu@contextsmith.com')
      u.refresh_token! if u.token_expired?
      token_emails << { token: "test", email: u.email }
      in_domain = "&in_domain=contextsmith.com"
    end

    ex_clusters = [project.contacts.map(&:email)]
    after = after.nil? ? "" : ("&after=" + after.to_s)
    query = query.nil? ? "" : ("&query=" + query.to_s)
    is_time = is_time.nil? ? "": ("&time=" + is_time.to_s)
    
    final_url = base_url + "?token_emails=" + token_emails.to_json + "&max=" + max.to_s + "&ex_clusters=" + url_encode(ex_clusters.to_s) + in_domain + after + url_encode(query) + is_time
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
      puts "Found #{data[0]['conversations'].size} conversations!\n"
      Notification.load(data, project, is_test)
      return Activity.load(data, project, save_in_db)
    elsif data['code'] == 401
      puts "Error: #{data['errors'][0]['message']}\n"
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