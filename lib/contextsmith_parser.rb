module ContextSmithParser
	def get_all_members(data)
		external_members = []
		internal_members = []

		d = data.map { |hash| Hashie::Mash.new(hash) }

    d.each do |project|
    	project.externalMembers.each { |m| external_members << m }
    	project.internalMembers.each { |m| internal_members << m }
    end

    uniq_external_members = external_members.uniq{ |m| m.address }
    uniq_internal_members = internal_members.uniq{ |m| m.address }

    return uniq_external_members, uniq_internal_members
	end
end