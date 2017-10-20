require 'securerandom'

class ContextsmithService

  def self.load_emails_from_backend(project, max=100, query=nil, save_in_db=true, after=nil, is_time=true, neg_sentiment=0, request=true, is_test=false)
    base_url = ENV["csback_script_base_url"] + "/newsfeed/search"

    after = after.nil? ? "" : ("&after=" + after.to_s)
    query = query.nil? ? "" : ("&query=" + url_encode(query.to_s))
    is_time = is_time.nil? ? "" : ("&time=" + is_time.to_s)
    request = request.nil? ? "": ("&request=" + request.to_s)
    neg_sentiment = neg_sentiment.nil? ? "": ("&neg_sentiment=" + neg_sentiment.to_s)
    params = "?max=" + max.to_s + after + query + is_time + neg_sentiment + request

    load_for_project_from_backend(project, base_url + params) do |data|
      puts "Found #{data[0]['conversations'].size} conversations!\n"
      Contact.load(data, project, save_in_db)
      # always load activity before notification
      result = Activity.load(data, project, save_in_db)
      Notification.load(data, project, is_test)
      result
    end
  end

  # 6.months.ago or more is too long ago, returns nil. 150.days is just less than 6.months and should work.
  def self.load_calendar_from_backend(project, max=100, after=150.days.ago.to_i, before=1.week.from_now.to_i, save_in_db=true)
    base_url = ENV["csback_script_base_url"] + "/newsfeed/event"
    params =  "?max=" + max.to_s + "&before=" + before.to_s + "&after=" + after.to_s

    load_for_project_from_backend(project, base_url + params) do |data|
      puts "Found #{data[0]['conversations'].size} calendar events!\n"
      Activity.load_calendar(data, project, save_in_db)
    end
  end

  def self.load_calendar_for_user(user, max: 100, after: Time.current.to_i, before: 1.day.from_now.to_i, save_in_db: false)
    base_url = ENV["csback_script_base_url"] + "/newsfeed/event"
    params =  "?max=" + max.to_s + "&before=" + before.to_s + "&after=" + after.to_s

    if user.nil? || Rails.env.development?
      source = [{ token: "test", email: "indifferenzetester@gmail.com", kind: "gmail" }]
      self_cluster = [["indifferenzetester@gmail.com"]]
    else
      source = [user_auth_params(user)]
      self_cluster = [[user.email]]
    end

    load_from_backend(source, self_cluster, base_url + params) { |data| Activity.load_calendar(data, Hashie::Mash.new(id: '00000000-0000-0000-0000-000000000000'), save_in_db) }
  end

  def self.get_emails_from_backend_with_callback(user)
    max = ENV["max_emails"] ? ENV["max_emails"].to_i : 10000
    base_url = ENV["csback_base_url"] + "/newsfeed/cluster"
    callback_url = "#{ENV['BASE_URL']}/onboarding/#{user.id}/create_clusters.json"

    if Rails.env.production?
      sources = [user_auth_params(user)]
      in_domain = ""
    elsif Rails.env.test? # Test / DEBUG
      sources = [user_auth_params(user)]
      in_domain = (user.email == 'indifferenzetester@gmail.com' ? "&in_domain=comprehend.com" : "")
    else # Dev environment
      if ENV['IGNORE_COMPREHEND_USER'] == 'true'
         sources = [user_auth_params(user)]
         sources[0][:email] = 'indifferenzetester@gmail.com'
         in_domain = "&in_domain=comprehend.com"  # still necessary as the test data is based on comprehend.com
      else
        u = User.find_by_email('indifferenzetester@gmail.com')
        sources = [{ token: u.fresh_token, email: u.email, kind: 'gmail' }]
        in_domain = "&in_domain=comprehend.com" # to simulate that users with this email domain are internal users
      end
    end
    final_url = base_url + "?preview=true&time=true&neg_sentiment=0&cluster_method=BY_EMAIL_DOMAIN&max=" + max.to_s + "&callback=" + callback_url + in_domain
    r = request_id(user.nil? ? '' : user.email)
    puts 'Calling backend service for clustering: ' + final_url + ' X-Request-ID:' + r

    uri = URI(final_url)
    req = Net::HTTP::Post.new(uri, 'Content-Type' => 'application/json', 'X-Request-ID' => r)
    req.body = { sources: sources }.to_json
    res = Net::HTTP.start(uri.host, uri.port) { |http| http.request(req) }
  end

  def self.request_id(prefix=nil)
    if prefix
      prefix + '_' + SecureRandom.urlsafe_base64(10)
    else
      SecureRandom.urlsafe_base64(10)
    end
  end

  private

  def self.load_for_project_from_backend(project, url)
    if Rails.env.development? && ENV['IGNORE_COMPREHEND_USER'] != 'true'
      sources = [{ token: "test", email: "indifferenzetester@gmail.com", kind: "gmail" }]
    else
      sources = project.users.registered.not_disabled.allow_refresh_inbox.map { |u| user_auth_params(u) }
    end
    ex_clusters = [project.contacts.pluck(:email)]

    load_from_backend(sources, ex_clusters, url) { |data| yield data }
  end

  def self.load_from_backend(sources, ex_clusters, url)
    sources.compact!
    return [] if sources.empty?

    in_domain = Rails.env.development? ? "&in_domain=comprehend.com" : ""

    final_url = url + in_domain
    r = request_id
    puts 'Calling backend service: ' + final_url + ' X-Request-ID:' + r

    p sources

    begin
      uri = URI(final_url)
      req = Net::HTTP::Post.new(uri, 'Content-Type' => 'application/json', 'X-Request-ID' => r)
      req.body = { sources: sources, external_clusters: ex_clusters }.to_json
      res = Net::HTTP.start(uri.host, uri.port
        #, use_ssl: uri.scheme == "https"
        ) { |http| http.request(req) }
      case res
        when Net::HTTPSuccess
          data = JSON.parse(res.body.to_s)
        when Net::HTTPServerError
          data = nil
          puts "Server error #{response.message}"
        else
          data = nil
      end
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

  def self.user_auth_params(user)
    case user.oauth_provider
    when User::AUTH_TYPE[:Gmail]
      success = user.token_expires_soon? ? user.refresh_token! : true
      unless success
        puts "Warning: Gmail token refresh failed for: #{ user.first_name } #{ user.last_name } #{ user.email } (Organization=#{ user.organization.name }, Role=#{ user.role.nil? ? "nil" : user.role }, Onboarding Step=#{ user.onboarding_step.nil? ? "nil" : user.onboarding_step }, Last sign-in=#{ user.last_sign_in_at.nil? ? "none" : user.last_sign_in_at })."
        return nil
      end
      { token: user.oauth_access_token, email: user.email, kind: 'gmail'}
      when User::AUTH_TYPE[:Office365]
        success = user.token_expires_soon? ? user.refresh_token! : true
        unless success
          puts "Warning: Office365 token refresh failed for: #{ user.first_name } #{ user.last_name } #{ user.email } (Organization=#{ user.organization.name }, Role=#{ user.role.nil? ? "nil" : user.role }, Onboarding Step=#{ user.onboarding_step.nil? ? "nil" : user.onboarding_step }, Last sign-in=#{ user.last_sign_in_at.nil? ? "none" : user.last_sign_in_at })."
          return nil
        end
        { token: user.oauth_access_token, email: user.email, kind: 'office365'}
      when User::AUTH_TYPE[:Exchange]
      { password: user.password, email: user.email, kind: 'exchange', url: user.oauth_provider_uid }
      else
        throw "ERROR: Uknown oauth provider #{user.oauth_provider}"
    end
  end
end
