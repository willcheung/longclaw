require 'whois'

module Utils
  ONBOARDING = { "onboarded": -1, "create_organization": 0, "intro_overall": 1, "intro_accounts": 2,
               	 "intro_projects": 3, "intro_activities": 4, "intro_pinned": 5, "confirm_projects": 6 }


	def get_full_name(user)
		[user.first_name, user.last_name].join(" ")
	end

	def get_first_name(name)
		return "" if name.include?("@")

	  if name.include?(', ') # Handles last name with comma
	    name.split(', ').last.split(' ').first 
	  else
	    name.split(' ').first 
	  end
	end

	def get_last_name(name)
		return "" if name.include?("@")

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

	def get_short_name(domain)
	  domain.gsub('.com', '')
	end

	def get_short_name_account_path(member)
		if member.is_internal_user?
			"@"+get_short_name(get_domain(member.email))
		else
			link_to("@"+get_short_name(member.account.domain), account_path(member.account))
		end
	end

	def get_value_or_na(val)
	  if val.nil?
	    "N/A"
	  else
	    val
	  end
	end

	def get_org_name(domain)
		r = Whois.whois(domain)
		p = r.parser

		begin
			org_name = p.registrant_contacts[0].organization
		rescue => e
			logger.error "ERROR: Can't get whois org name for domain #{domain}: " + e.message
      logger.error e.backtrace.join("\n")
      return domain
    else
    	return org_name
    end
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
end