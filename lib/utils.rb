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

		####
		# NOTE: 'whois' is not accurate and sometimes returns giberish.  We need to use another solution.
		####
		# begin
		# 	r = Whois.whois(domain)
		# rescue => e
		# 	return domain, ""
		# end

		# begin
		# 	if !r.registrant_contacts.nil?
		# 		if r.registrant_contacts[0].nil?
		# 			return domain, ""
		# 		end

		# 		if r.registrant_contacts[0].organization.nil? or r.registrant_contacts[0].organization == "" or r.registrant_contacts[0].organization.downcase.include?("proxy") or r.registrant_contacts[0].organization.downcase.include?("domain") or r.registrant_contacts[0].organization.downcase.include?("dreamhost") or r.registrant_contacts[0].organization.downcase.include?("hover") or r.registrant_contacts[0].organization.downcase.include?("namecheap") or r.registrant_contacts[0].organization.downcase.include?("names.com") or r.registrant_contacts[0].organization.downcase.include?("godaddy") or r.registrant_contacts[0].organization.downcase.include?("whois")
		# 			return domain, ""
		# 		else
		# 			org_name = r.registrant_contacts[0].organization
		# 		end

		# 		address = ([r.registrant_contacts[0].address, r.registrant_contacts[0].city, r.registrant_contacts[0].state, 
		# 							 r.registrant_contacts[0].country, r.registrant_contacts[0].country_code]).join(' ')

		# 		return org_name, address
		# 	else
	 #      return domain, ""
	 #    end
	 #  rescue => e
	 #  	return domain, ""
	 #  end

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

  def min_risk_score(scores)
    scores.reduce(0.0) do |min_score, a|
      sentiment_score = JSON.parse(a.sentiment_item)[0]['score']  
      min_score < sentiment_score ? min_score : sentiment_score
    end
  end

  # adjust scale and round float to a percentage
  def round_and_scale_score(score)
    score = (((-score - 0.75) * 4) * 100).round
    score < 0.0 ? 0 : score
  end
end