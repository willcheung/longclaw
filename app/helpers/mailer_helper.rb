module MailerHelper
	include ApplicationHelper

  def rounded_initials_for_email(name, email)
  	member = name || email
    css_style = "border-radius:50%;width:24px;height:24px;margin:0 2px;padding:5px;border:1px solid #666;color:#fff;text-align:center;font-size:14px;float:left;line-height:25px;cursor:default;"
    css_style += 'background:' + User::PROFILE_COLOR[(member.length)%9]

    u = User.find_by_email(email)
    if u.nil? or u.image_url.nil? or u.image_url.empty?
    	s = '<div title="' + member + '" style="' + css_style + '">'

    	if member.include?(', ') # first and last name reverse because of comma
      	s += member.split(', ').last[0,1] + member.split(', ').first[0,1]
      else
      	s += member.split(' ').first[0,1] + member.split(' ').last[0,1]
      end

      s += "</div>"

      return s.html_safe
    else
      return ('<div><img alt="image" style="border-radius:50%;width:32px;height:32px;" src="' + u.image_url + '"/></div>').html_safe
    end
  end

  def is_internal_user?(email)
    u = User.find_by_email(email)
    if u.nil?
      return false
    else
      return true
    end
  end
end