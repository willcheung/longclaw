module MailerHelper
	def get_first_names(to, cc)
        a = []

        to.each do |n| 
            if n["personal"].nil?
            	a << n["address"]
            else 
            	if n["personal"].include?(', ') # Handles last name first
            		a << n["personal"].split(', ').last
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

    def rounded_initials_single(name)
    	if name["personal"].nil?
          member = name["address"]
      else
          member = name["personal"]
      end

    	css_style = "border-radius:50%;width:24px;height:24px;margin-right:3px;margin-bottom:3px;padding:5px;border: 1px solid #666;color:#fff;text-align:center;font:14px Arial,sans-serif;float:left;line-height:25px;cursor:default;"
    	css_style += 'background:' + User::PROFILE_COLOR[(member.length)%9]
    	
    	s = '<div title="' + member + '" style="' + css_style + '">'

    	if member.include?(', ') # first and last name reverse because of comma
      	s += member.split(', ').last[0,1] + member.split(', ').first[0,1]
      else
      	s += member.split(' ').first[0,1] + member.split(' ').last[0,1]
      end

      return s.html_safe
    end

    def rounded_initials_group(internal, external, css_class="", css_style="")
        a = []
        s = ""

        external.each do |n|
            if n["personal"].nil?
                a << n["address"]
            else
                a << n["personal"]
            end
        end

        a << '<span style="line-height:34px;float:left;margin:0 5px 0 2px;">//</span>'

        unless internal.nil? or internal.empty?
            internal.each do |n|
                if n["personal"].nil?
                    a << n["address"]
                else
                    a << n["personal"]
                end
            end
        end

        a.each do |member|
        	if member.include?("//")
        		s += member
        	else
            s += '<div title="' + member + '" style="' + css_style + ';background:' + User::PROFILE_COLOR[rand(20)%5] + '" class="' + css_class + '">'
            
            if member.include?(', ') # first and last name reverse because of comma
            	s += member.split(', ').last[0,1] + member.split(', ').first[0,1]
            else
            	s += member.split(' ').first[0,1] + member.split(' ').last[0,1]
            end
            
            s += '</div>'
          end
        end

        return s.html_safe
    end

    def get_name_or_everyone(to, cc)
    	cc_size = (cc.nil? ? 0 : cc.size)
    	total_size = to.size + cc_size
    	size_limit = 4

    	if to.size <= size_limit and cc_size == 0
    		return get_first_names(to, cc)
    	elsif to.size <= size_limit and cc_size > 0
    		remaining = size_limit - to.size 
    		if remaining == 0
    			return get_first_names(to, nil) + " and " + pluralize(total_size - size_limit, 'other')
    		else # ramaining > 0
    			if cc_size > remaining
    				return get_first_names(to, cc[0..(remaining-1)]) + " and " + pluralize(cc_size - remaining, 'other')
    			else # cc_size <= reamining
    				return get_first_names(to, cc)
    			end
    		end
    	elsif to.size >= size_limit
    		remaining = 0
    		return get_first_names(to[0..size_limit], nil) + " and " + pluralize(total_size - size_limit, 'other')
    	end
    end

    def internal_member?(data, index, member)
    	data[index]["internalMember"].include?(member)
    end
end