#require 'whois'

module Utils
  ONBOARDING = { "onboarded": -1, "fill_in_info": 0, "tutorial": 1, "confirm_projects": 2 }


	def get_user_or_contact_from_pm(project_member)
		if !project_member.user.nil?
			project_member.user
		else
			project_member.contact
		end
	end

	def get_full_name(user)
		return "" if user.nil?

		[user.first_name, user.last_name].join(" ")
	end

	def get_first_name(name)
		return "" if name.nil? or name.include?("@")

	  if name.include?(', ') # Handles last name with comma
	    name.split(', ').last.split(' ').first
	  else
	    name.split(' ').first
	  end
	end

	def get_last_name(name)
		return "" if name.nil? or name.include?("@")

	  if name.include?(', ') # Handles last name with comma
	    name.split(', ').first.split(' ').last
	  else
	    name.split(' ').last
	  end
	end

	def get_yn(bool)
	  bool ? 'Yes' : 'No'
	end

	def get_domain(email)
		email.split("@").last
	end

	def get_local_part(email)
		email.split("@").first
	end

	def get_short_name(domain)
	  domain.gsub('.com', '')
	end

	def get_short_name_account_path(member)
		if member.is_internal_user?
			"@"+get_short_name(get_domain(member.email))
		else
			link_to("@"+get_short_name(get_domain(member.email)), account_path(member.account))
		end
	end

	def get_value_or_na(val)
	  if val.nil?
	    "N/A"
	  else
	    val
	  end
	end

	def get_org_info(domain) # returns ["Name","Address"]
		return domain, ""
	end

	def dice_coefficient(a, b)
    a_set = a.to_set
    b_set = b.to_set

    intersect = (a_set & b_set).size.to_f
    union = (a_set | b_set).size.to_f
    dice  = intersect / union

    return dice
	end

	def intersect(a, b)
		(a & b).size
	end

  def scale_sentiment_score(score)
    score = (((-score - 0.75) * 4) * 100).floor
    score < 0.0 ? 0 : score
  end

  # Compares domain to our blacklist and returns true if valid (doesn't match any blacklisted pattern; is correct length), false otherwise
  def valid_domain?(domain)
    bl_regex_patterns =[
                        # e-mail servers
                        '(.)*gmail.com', 
                        '(.)*hotmail.com', 'hotmail.(.)*',
                        '(.)*yahoo.com', 'yahoo.(.)*', 
                        # other servers or domains
                        '(.)*calendar(.)*.google.com',
                        '(.)*serverdata.net', 
                        '(.)*comcastbiz.net', 
                        '(.)*.salesforce.com', 
                        '(.)*.zendesk.com', 
                       ]
    return false if domain.length > 64
    bl_regex_patterns.none? { |p| Regexp.new(p, Regexp::IGNORECASE).match(domain) }
  end

  # Returns the domain from subdomain. If special rule/exception is found, returns the subdomain unchanged.
  def get_domain_from_subdomain(subdomain)
    wl_regex_patterns =[ 
                        '(.)*(\.co\.)(.)*',   
                        '(.)*(\.com\.)(.)*', 
                        '(.)*(\.net\.)(.)*',
                        '(.)*(\.edu\.)(.)*'
                       ]
    return subdomain if wl_regex_patterns.any? { |p| Regexp.new(p, Regexp::IGNORECASE).match(subdomain) }
    subdomain.split('.').last(2).join('.')  # obtain simple domain from subdomain
  end
end
