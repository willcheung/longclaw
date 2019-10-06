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

  def user_agent_helper(ua, domain)
    parser = UserAgentParser::Parser.new
    #parser.parse("Mozilla/4.0 (compatible; MSIE 7.0; Windows NT 6.1; WOW64; Trident/6.0; SLCC2; .NET CLR 2.0.50727; .NET CLR 3.5.30729; .NET CLR 3.0.30729; Media Center PC 6.0; .NET4.0C; .NET4.0E; Microsoft Outlook 16.0.8326; Microsoft Outlook 16.0.8326; ms-office; MSOffice 16)").os
    user_agent = parser.parse(ua)

    if user_agent.device.to_s == 'Other'
      "on #{domain} network"
    elsif user_agent.os.to_s.include? "Mac OS X"
      if domain == ""
        "<img src=\"https://app.contextsmith.com/assets/fa-desktop.png\" width=\"15\" height=\"15\" border=\"0\" style=\"display:block\"/>&nbsp; Mac".html_safe
      else
        "<img src=\"https://app.contextsmith.com/assets/fa-desktop.png\" width=\"15\" height=\"15\" border=\"0\" style=\"display:block\"/>&nbsp; Mac on #{domain} network".html_safe
      end
    elsif user_agent.os.to_s.include? "Windows"
      if domain == ""
        "Windows"
      else
        "Windows on #{domain} network"
      end
    else
      if domain == ""
        ("<img src=\"https://app.contextsmith.com/assets/fa-mobile.png\" width=\"15\" height=\"15\" border=\"0\" style=\"display:block\"/>&nbsp;" + user_agent.device.to_s).html_safe
      else
        ("<img src=\"https://app.contextsmith.com/assets/fa-mobile.png\" width=\"15\" height=\"15\" border=\"0\" style=\"display:block\"/>&nbsp;" + user_agent.device.to_s + " on #{domain} network").html_safe
      end
    end
  end
end