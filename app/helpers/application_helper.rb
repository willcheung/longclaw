module ApplicationHelper
  include Utils

  def is_active_controller(controller_name)
    params[:controller] == controller_name ? "active" : nil
  end

  def is_active_action(action_name)
    params[:action] == action_name ? "active" : nil
  end

  def is_internal_domain?(email)
    current_user.organization.domain.downcase == get_domain(email).downcase
  end

  def get_first_names(from, to, cc)
      a = []

      a << get_first_name(from[0]["personal"]) if !from.empty?

      unless to.nil? or to.empty?
        to.each do |n| 
          if n["personal"].nil?
            a << n["address"]
          else 
            a << get_first_name(n["personal"])
          end
        end
      end 

      unless cc.nil? or cc.empty?
        cc.each do |n| 
          if n["personal"].nil?
            a << n["address"]
          else 
            a << get_first_name(n["personal"])
          end
        end
      end

      return a.join(', ')
  end

  def get_conversation_member_names(from, to, cc, trailing_text="other", size_limit=4)
    cc_size = (cc.nil? ? 0 : cc.size)
    to_size = (to.nil? ? 0 : to.size)
    from_size = (from.nil? ? 0 : from.size)

    total_size = from_size + to_size + cc_size
    
    if to_size <= size_limit and cc_size == 0
      return get_first_names(from, to, cc)
    elsif to_size <= size_limit and cc_size > 0
      remaining = size_limit - to_size 
      if remaining == 0
        if trailing_text=="other"
          return get_first_names(from, to, nil) + " and " + pluralize(total_size - size_limit, 'other')
        else
          return "All"
        end
      else # ramaining > 0
        if cc_size > remaining
          if trailing_text=="other"
            return get_first_names(from, to, cc[0..(remaining-1)]) + " and " + pluralize(cc_size - remaining, 'other')
          else
            return "All"
          end
        else # cc_size <= remaining
          return get_first_names(from, to, cc)
        end
      end
    elsif to_size >= size_limit
      remaining = 0
      if trailing_text=="other"
        return get_first_names(from, to[0..size_limit], nil) + " and " + pluralize(total_size - size_limit, 'other')
      else
        return "All"
      end
    end
  end

  def get_profile_pic(name, email, css_class="")
    if is_internal_domain?(email)
      u = User.find_by_email(email)
      if u.nil? or u.image_url.nil? or u.image_url.empty?
        get_rounded_initials_from_name(name, css_class)
      else
        return ('<div class="' + css_class + '"><img alt="image" class="img-circle" style="width:30px;height:30px;" src="' + u.image_url + '"/></div>').html_safe
      end
    else
      get_rounded_initials_from_name(name, css_class)
    end
  end

  def get_rounded_initials_from_name(name, css_class="")
    if name.nil? or name.empty? or name == " "
      s = '<i class="fa fa-user"></i>' 
      name = ""
    elsif name.include?(', ') # first and last name reverse because of comma
      s = name.split(', ').last[0,1] + name.split(', ').first[0,1]
    else
      s = name.split(' ').first[0,1] + name.split(' ').last[0,1]
    end

    return ('<div class="rounded-initials ' + css_class + '" title="' + name + '" style="background:' + User::PROFILE_COLOR[(name.length)%9] + '">' + s + '</div>').html_safe
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
