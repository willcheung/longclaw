module ContextSmithParser
	def get_all_members(data)
		external_members = []
		internal_members = []

		d = data.map { |hash| Hashie::Mash.new(hash) }

    d.each do |project|
    	project.externalMembers.each { |m| external_members << m } if !project.externalMembers.nil?
    	project.internalMembers.each { |m| internal_members << m } if !project.internalMembers.nil?
    end

    uniq_external_members = external_members.uniq{ |m| m.address }
    uniq_internal_members = internal_members.uniq{ |m| m.address }

    return uniq_external_members, uniq_internal_members
	end

	def get_project_members(data, project_domain)
		external_members = []
		internal_members = []

		d = data.map { |hash| Hashie::Mash.new(hash) }

		d.each do |project|
			if project.topExternalMemberDomain == project_domain
				project.externalMembers.each { |m| external_members << m } if !project.externalMembers.nil?
    		project.internalMembers.each { |m| internal_members << m } if !project.internalMembers.nil?
			end
		end

		return external_members, internal_members
	end

	def get_project_top_domain(data)
		project_domains = []
		data.each { |p| project_domains << p["topExternalMemberDomain"] }
		return project_domains
	end

	def get_project_conversations(data, project_domain)
		single_project = [] # Needs to be in an array because this is how backend data is being processed in Activity.load

		data.each do |p|
			if p["topExternalMemberDomain"] == project_domain
				single_project[0] = p
			end
		end
		return single_project
	end
end