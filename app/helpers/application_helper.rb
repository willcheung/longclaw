module ApplicationHelper
    def is_active_controller(controller_name)
      params[:controller] == controller_name ? "active" : nil
    end

    def is_active_action(action_name)
      params[:action] == action_name ? "active" : nil
    end

    def get_full_name(user)
    	[user.first_name, user.last_name].join(" ")
    end

    def get_yn(bool)
      bool ? 'Yes' : 'No'
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

    def is_internal_user?(email)
      current_user.organization.domain.downcase == email.split("@").last.downcase
    end

    def get_first_names(from, to, cc)
        a = []

        if from[0]["personal"].include?(', ') # Handles last name first
          a << from[0]["personal"].split(', ').last.split(' ').first 
        else
          a << from[0]["personal"].split(' ').first 
        end

        to.each do |n| 
          if n["personal"].nil?
            a << n["address"]
          else 
            if n["personal"].include?(', ') # Handles last name first
              a << n["personal"].split(', ').last.split(' ').first 
            else
              a << n["personal"].split(' ').first 
            end
          end
        end

        unless cc.nil? or cc.empty?
          cc.each do |n| 
            if n["personal"].nil?
              a << n["address"]
            else 
              if n["personal"].include?(', ')
                a << n["personal"].split(', ').last
              else
                a << n["personal"].split(' ').first 
              end
            end
          end
        end

        return a.join(', ')
    end

    def get_conversation_member_names(from, to, cc, size_limit=4)
      cc_size = (cc.nil? ? 0 : cc.size)
      total_size = from.size + to.size + cc_size
      
      if to.size <= size_limit and cc_size == 0
        return get_first_names(from, to, cc)
      elsif to.size <= size_limit and cc_size > 0
        remaining = size_limit - to.size 
        if remaining == 0
          return get_first_names(from, to, nil) + " and " + pluralize(total_size - size_limit, 'other')
        else # ramaining > 0
          if cc_size > remaining
            return get_first_names(from, to, cc[0..(remaining-1)]) + " and " + pluralize(cc_size - remaining, 'other')
          else # cc_size <= reamining
            return get_first_names(from, to, cc)
          end
        end
      elsif to.size >= size_limit
        remaining = 0
        return get_first_names(from, to[0..size_limit], nil) + " and " + pluralize(total_size - size_limit, 'other')
      end
    end

    def get_profile_pic(name, email, css_class="")
      if is_internal_user?(email)
        u = User.find_by_email(email)
        if u.nil? or u.image_url.nil? or u.image_url.empty?
          get_rounded_initials_from_name(name, css_class)
        else
          return ('<div class="' + css_class + '"><img alt="image" class="img-circle" style="width:30px;" src="' + u.image_url + '"/></div>').html_safe
        end
      else
        get_rounded_initials_from_name(name, css_class)
      end
    end

    def get_rounded_initials_from_name(name, css_class="")
      if name.include?(', ') # first and last name reverse because of comma
        s = name.split(', ').last[0,1] + name.split(', ').first[0,1]
      else
        s = name.split(' ').first[0,1] + name.split(' ').last[0,1]
      end

      return ('<div class="rounded-initials ' + css_class + '" style="background:' + User::PROFILE_COLOR[(name.length)%9] + '">' + s + '</div>').html_safe
    end

    def custom_toastr_flash
    	flash_messages = []
    	flash.each do |type, message|
    		type = 'success' if type == 'notice'
    		type = 'error'   if type == 'alert'
    		text = "<script>toastr.#{type}('#{message}');</script>"
    		flash_messages << text.html_safe if message
    	end
    	flash_messages.join("\n").html_safe
    end
end
