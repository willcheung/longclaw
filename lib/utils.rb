module Utils
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

	def get_value_or_na(val)
	  if val.nil?
	    "N/A"
	  else
	    val
	  end
	end
end