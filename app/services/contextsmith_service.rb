require 'logger'

class ContextsmithService

  def self.load_emails_from_backend(project, logger, after=nil, max=100)
    token_emails = []
    base_url = ENV["csback_base_url"] + "/newsfeed/search"

    if ENV["RAILS_ENV"] == 'production' or ENV["RAILS_ENV"] == 'test'
      in_domain = ""
      project.users.registered.each do |u|
        u.refresh_token! if u.token_expired?
        token_emails << { token: u.oauth_access_token, email: u.email }
      end
      return [] if token_emails.empty?
    else
      # DEBUG
      u = User.find_by_email('indifferenzetester@gmail.com')
      u.refresh_token! if u.token_expired?
      token_emails << { token: u.oauth_access_token, email: u.email }
      in_domain = "&in_domain=comprehend.com"
    end

    ex_clusters = [project.contacts.map(&:email)]
    after = after.nil? ? "" : ("&after=" + after.to_s)
    
    final_url = base_url + "?token_emails=" + token_emails.to_json + "&max=" + max.to_s + "&ex_clusters=" + ex_clusters.to_s + in_domain + after
    logger.info "Calling backend service: " + final_url

    begin
      url = URI.parse(final_url)
      req = Net::HTTP::Get.new(url.to_s)
      res = Net::HTTP.start(url.host, url.port) { |http| http.request(req) }
      data = JSON.parse(res.body.to_s)
    rescue => e
      logger.error "ERROR: Something went wrong: " + e.message
      logger.error e.backtrace.join("\n")
    end

    if data.nil? or data.empty?
      logger.error "No data returned!\n"
    else
      logger.info "Found #{data[0]['conversations'].size} conversations!\n"
      Activity.load(data, project)
    end
    
    return data
  end

end