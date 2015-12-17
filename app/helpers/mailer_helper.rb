module MailerHelper
	
    def rounded_initials_single(name)
    	if name["personal"].nil?
          member = name["address"]
      else
          member = name["personal"]
      end

    	css_style = "border-radius:50%;width:24px;height:24px;margin:0 3px;padding:5px;border:1px solid #666;color:#fff;text-align:center;font-size:14px;float:left;line-height:25px;cursor:default;"
    	css_style += 'background:' + User::PROFILE_COLOR[(member.length)%9]
    	
    	s = '<div title="' + member + '" style="' + css_style + '">'

    	if member.include?(', ') # first and last name reverse because of comma
      	s += member.split(', ').last[0,1] + member.split(', ').first[0,1]
      else
      	s += member.split(' ').first[0,1] + member.split(' ').last[0,1]
      end

      s += "</div>"

      return s.html_safe
    end

    def member_of_group?(group, member)
    	group.include?(member)
    end

    def activities_by_projects(data)
        projects = Hash.new
        total_messages = 0
        project_messages = 0
        total_conversations = 0

        data.each do |p|
          name = get_account_name(p["topExternalMemberName"], p["topExternalMemberDomain"])
          total_conversations += p["conversations"].size
          project_messages = 0
          p["conversations"].each do |c|
            total_messages += c["contextMessages"].size
            project_messages += c["contextMessages"].size
          end

          projects["#{name}"] = project_messages
        end

        projects.each do |project,value|
          projects["#{project}"] = '%.1f' % ((value / total_messages.to_f) * 100.0)
        end

        return projects.sort_by { |name, value| value.to_i }
    end

    def get_account_name(name, domain)
      if name.nil? or name.downcase.include?("domain") or name.downcase.include?("registrar") or name.downcase.include?("registrant")
        domain.gsub('.com','').capitalize
      else 
        name
      end
    end
end