module ProjectsHelper
	def not_in_current_user_inbox(a)
		!a.email_messages.map{|m| m.sourceInboxes }.flatten.include?(current_user.email) and a.category == "Conversation"
	end
end
