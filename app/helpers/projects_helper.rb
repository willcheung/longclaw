module ProjectsHelper
	def not_in_current_user_inbox(a)
		!(
			a.email_messages.map{|m| m.to.map { |to| to.address }.flatten }.include?(current_user.email) or
			a.email_messages.map{|m| m.from.map { |from| from.address }.flatten }.include?(current_user.email) or
			a.email_messages.map{|m| m.cc.map { |cc| cc.address }.flatten }.include?(current_user.email)
		)
	end
end
