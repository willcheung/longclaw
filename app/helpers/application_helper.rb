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

    def get_value_or_na(val)
        if val.nil?
            "N/A"
        else
            val
        end
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
