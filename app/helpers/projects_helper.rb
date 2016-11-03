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
    "Re:+" + URI.escape(a.title, Regexp.new("[^#{URI::PATTERN::UNRESERVED}]"))
  end

  def last_msg_body(a)
    last_msg = a.email_messages.last
    sent_date = Time.zone.at(last_msg.sentDate).strftime("%b %-d, %Y %I:%M %p")
    from_hash = last_msg.from.first
    from = ""
    from += " \"" + from_hash.personal + "\"" if from_hash.personal
    from += " <" + from_hash.address + ">" if from_hash.address
    body = ""
    body = URI.escape(last_msg.content.body, Regexp.new("[^#{URI::PATTERN::UNRESERVED}]")) unless last_msg.content.nil? || !last_msg.content.respond_to?(:body) 
    "%0A%0AOn " + sent_date + "," + from + " wrote:%0A%0A" + body
  end
end
