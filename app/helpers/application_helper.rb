module ApplicationHelper
  include Utils
  CONTEXTSMITH_BLUE = "#7cb5ec"  # "CS blue" / light blue

  def get_contextsmith_blue
    CONTEXTSMITH_BLUE
  end

  def is_active_controller(controller_name)
    params[:controller] == controller_name ? "active" : nil
  end

  def is_active_action(action_name)
    params[:action] == action_name ? "active" : nil
  end

  def is_internal_domain?(email)
      current_user.organization.domain.downcase == get_domain(email).downcase 
  end

  def green_or_red(num)
    num > 0 ? "text-success" : "text-danger"
  end

  def up_or_down(num)
    num > 0 ? "<i class=\"fa fa-level-up\"></i>".html_safe : "<i class=\"fa fa-level-down\"></i>".html_safe
  end

  def highcharts_series_color(category="default")
    case category
    when Activity::CATEGORY[:Conversation], 'Sent E-mails', 'E-mails Sent'
      '#46C6C6'
    when 'Read E-mails', 'E-mails Received'
      '#33a6a6'
    when Activity::CATEGORY[:Meeting], 'Meetings'
      '#ffb833'
    when Notification::CATEGORY[:Attachment], 'Attachments'
      '#33a66d'
    when Activity::CATEGORY[:Note]
      '#ffde6b'
    when Activity::CATEGORY[:JIRA]
      '#205081'
    when Activity::CATEGORY[:Salesforce]
      '#1798c1'
    when Activity::CATEGORY[:Zendesk]
      '#78a300'
    when Activity::CATEGORY[:Alert]
      '#ed5565'
    when Activity::CATEGORY[:Basecamp2]
      '#91e8e1'
    when 'metric'
      '#434348'
    else
      CONTEXTSMITH_BLUE
    end
  end

  def highcharts_series_color_gradient_by_pct(val, minval, maxval)
    if val < minval
      '#398fe2'
    # lighter tints (first), darker tints (last)
    elsif (val - minval) / (maxval - minval).to_f < 0.1
      '#aed2f0'
    elsif (val - minval) / (maxval - minval).to_f < 0.2
      '#a6cdef' 
    elsif (val - minval) / (maxval - minval).to_f < 0.3
      '#9dc8ee'
    elsif (val - minval) / (maxval - minval).to_f < 0.4
      '#93c2ed'
    elsif (val - minval) / (maxval - minval).to_f < 0.5
      '#88bcec'
    elsif (val - minval) / (maxval - minval).to_f < 0.6
      '#7bb5ea'
    elsif (val - minval) / (maxval - minval).to_f < 0.7
      '#6dade8'
    elsif (val - minval) / (maxval - minval).to_f < 0.8
      '#5da4e6'
    elsif (val - minval) / (maxval - minval).to_f < 0.9
      '#4c9ae4'
    else
      '#398fe2' # >= 0.9 (incl. val > maxval)
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
      else # remaining > 0
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

  # creates a human-readable local time expression from an activity
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
    elsif name.include?(' ')
      s = name.split(' ').first[0,1] + name.split(' ').last[0,1] 
    else
      s = name[0,1]
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

  # Generates formatted (with HTML tags), expandable and collapsible text.  Uses simple_format() to break newlines, and truncate() to break up content.
  # Parameters:   text - the text content to truncate (and displayed)
  #               id - used as the unique identifier in DOM
  #               length (optional) - length at which to truncate text, defaults to 100
  #               max_length (optional) - maximum length of the text to display, defaults to the length of text
  #               separator (optional) - the separator option in the truncate() function, defaults to empty string
  # Note:  If text doesn't exist (nil), returns no content.  May need to use .html_safe in .erb embedded Ruby partials, and toggle_visibility_for_pair()/ toggle_visibility() .js scripts.
  def get_expandable_text_html(text: , id: , length: 100, max_length: nil, separator: '')
    return "<span></span>" if text.nil?  # no content
    max_length = text.length if max_length.nil?

    # Do some newline processing to ensure proper conversion to <br> by simple_format later
    text.gsub!(/\r\n/, "\n")  # convert the carriage-return + newline sequences (e.g., from SFDC activity) into single newlines
    text.gsub!(/\n+/, "\n")   # convert double newlines into single ones

    id = id.to_s
    # Truncated text content
    html = "<span id=\"" + id + "-short\" style=\"display:block\">" + simple_format(truncate(text, length: length, separator: separator), {style: "overflow-wrap: break-word"}, wrapper_tag: 'span')
    html += "<a href=\"#"+ id + "\" onclick=\"toggle_visibility_for_pair('" + id + "-short', '" + id + "-full');\">&nbsp;[more]</a></span>" + 
            "<span id=\""+ id +"-full\" style=\"display: none\">" + simple_format(truncate(text, length: max_length, separator: separator), {style: "overflow-wrap: break-word"}, wrapper_tag: 'span') + 
            "<a href=\"#"+ id + "\" onclick=\"toggle_visibility_for_pair('" + id + "-short', '" + id + "-full');\">&nbsp;[less]</a></span>" if text.length >length
    return html
  end

  # Truncate a string if it is longer than the maxlength, and append ellipses to the end. If it is shorter, then return the string with no change.
  def truncate_with_ellipsis(string, maxlength)
    string[0...maxlength] + (string.length > maxlength ? "…" : "")
  end

  # Returns date as string formatted as "Mmm dd" if it is less than a year into the future; otherwise, if it is more than year away from today or is in the past, returns date as "Mmm dd Yyyy" (used to shorten display of a date if space is limited)
  def get_formatted_date(date)
    (date - DateTime.now) <= 365 && date >= DateTime.now ? date.strftime('%b %d') : date.strftime('%b %d %Y')
  end

end
