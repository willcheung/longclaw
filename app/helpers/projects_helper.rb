module ProjectsHelper
	def not_in_current_user_inbox(a)
		!(
			a.email_messages.map{|m| m.to.nil? ? [] : (m.to.map { |to| to.address }) }.flatten.include?(current_user.email) or
			a.email_messages.map{|m| m.from.map { |from| from.address } }.flatten.include?(current_user.email) or
			a.email_messages.map{|m| m.cc.nil? ? [] : (m.cc.map { |cc| cc.address }) }.flatten.include?(current_user.email)
		)
	end

  def last_msg_recipients(a)
    addresses = Set.new
    last_msg = a.email_messages.last
    from = last_msg.from || []
    to = last_msg.to || []
    cc = last_msg.cc || []
    addresses.merge((from + to + cc).map(&:address))
    (addresses - [current_user.email]).to_a * ","
  end

  def last_msg_subject(a)
    URI.escape("Re: " + a.title, Regexp.new("[^#{URI::PATTERN::UNRESERVED}]"))
  end

  def last_msg_body(a)
    last_msg = a.email_messages.last
    sent_date = Time.zone.at(last_msg.sentDate).strftime("%b %-d, %Y %I:%M %p")
    from_hash = last_msg.from.first
    from = ""
    from += " \"" + from_hash.personal + "\"" if from_hash.personal
    from += " <" + from_hash.address + ">" if from_hash.address
    body = last_msg.content && last_msg.content.respond_to?(:body) ? last_msg.content.body : last_msg.content.to_s 
    URI.escape("\n\nOn " + sent_date + "," + from + " wrote:\n\n" + body, Regexp.new("[^#{URI::PATTERN::UNRESERVED}]"))
  end

  def smart_email_body(message)
    body = message.content.nil? || message.content.is_a?(String) ? message.content : message.content.body
    message.temporalItems.reverse_each do |i|
      task = i.taskAnnotation
      body.insert(task.endOffset, "</a>").insert(task.beginOffset, "<a class=\"suggested-action\">")
    end if message.temporalItems
    simple_format(body, {}, sanitize: false)
  end
end
