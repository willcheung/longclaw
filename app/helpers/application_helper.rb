module ApplicationHelper
  include Utils

  def is_active_controller(controller_name)
    params[:controller] == controller_name ? "active" : nil
  end

  def is_active_action(action_name)
    params[:action] == action_name ? "active" : nil
  end

  def is_internal_domain?(email)
    if email.nil? 
      current_user.organization.domain.downcase == get_domain(email).downcase 
    end
  end

  def green_or_red(num)
    num > 0 ? "text-success" : "text-danger"
  end

  def up_or_down(num)
    num > 0 ? "<i class=\"fa fa-level-up\"></i>".html_safe : "<i class=\"fa fa-level-down\"></i>".html_safe
  end

  def highcharts_series_color(category)
    if category == Activity::CATEGORY[:Conversation]
      "#46C6C6"
    elsif category == Activity::CATEGORY[:Meeting]
      "#FFA500"
    elsif category == Activity::CATEGORY[:Note]
      "#ffde6b"
    elsif category == Activity::CATEGORY[:JIRA]
      "#205081"
    elsif category == Activity::CATEGORY[:Salesforce]
      "#1798c1"
    elsif category == Activity::CATEGORY[:Zendesk]
      "#78a300"
    elsif category == Activity::CATEGORY[:Alert]
      "#ed5565"
    end
  end

  def risk_color(score, in_email=false)
    return unless score

    unless in_email
      if score >= 80.0
        "text-danger"
      elsif score >= 60.0
        "text-warning"
      else
        "text-success"
      end
    else
      if score >= 80.0
        "#ed5565"
      elsif score >= 60.0
        "#FFA500"
      else
        "#A1C436"
      end
    end
  end

  def alert_color(score)
    return unless score
    if score > 0
      "#ed5565"
    end
  end

  def risk_level(score)
    if score
      s = " Risk"
      if score >= 80.0
          "High" + s
      elsif score >= 60.0
          "Medium" + s
      else
          "Low" + s
      end
    end
  end

  def rag_note(score)
    if score
      s = "Status set to "
      if score == 3
        s + Project::RAGSTATUS[:Green]
      elsif score == 2
        s + Project::RAGSTATUS[:Amber]
      elsif score == 1
        s + Project::RAGSTATUS[:Red]
      else
        "Add Text"
      end
    end
  end


  def get_first_names(from, to, cc)
      a = []

      if !from.empty?
        if from[0]["personal"].nil?
          a << from[0]["address"]
        else
          a << get_first_name(from[0]["personal"])
        end
      end

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

  def get_calendar_member_names(to, trailing_text="other", size_limit=6)
    attendees_size = (to.nil? ? 0 : to.size)

    if attendees_size <= size_limit
      return get_first_names([], to, nil)
    else
      if trailing_text == "other"
        return get_first_names([], to[0..size_limit], nil) + " and " + pluralize(attendees_size - size_limit, 'other')
      else
        return "All"
      end
    end
  end

  def get_calendar_interval(event)
    start = event.last_sent_date
    end_t = Time.zone.at(event.email_messages.last.end_epoch)
    if start.to_date == end_t.to_date
      return start.strftime("%l:%M%P") + ' - ' + end_t.strftime("%l:%M%P")
    elsif start == start.midnight && end_t == end_t.midnight # if there is no time, date only
      return start.strftime("%b %e") + ' - ' + end_t.strftime("%b %e")
    else
      return start.strftime("%b %e,%l:%M%P") + ' - ' + end_t.strftime("%b %e,%l:%M%P")
    end
  end

  def get_profile_pic(name, email, css_class="")
    if is_internal_domain?(email)
      u = User.find_by_email(email)
      if u.nil? or u.image_url.nil? or u.image_url.empty?
        get_rounded_initials_from_name(name, css_class)
      else
        return ('<div class="' + css_class + '"><img alt="image" class="img-circle" style="width:32px;height:32px;" src="' + u.image_url + '"/></div>').html_safe
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

  # Highcharts helper
  def get_num_activities_by_project(date_range, trend_data, project_id)
    date_range.map { |date| trend_data.find_all { |p| p.id == project_id }.find { |d| d.date == date }.num_activities }.inspect
  end

  def get_num_activities(date_range, trend_data)
    date_range.map { |date| trend_data.find { |d| d.date == date }.num_activities }.inspect
  end

  # Alert Notification helper
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
