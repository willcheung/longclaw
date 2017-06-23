module ContextSmithParser
	def get_all_members(data)
		external_members = []
		internal_members = []

		d = data.map { |hash| Hashie::Mash.new(hash) }

    d.each do |project|
      external_members.concat(project.externalMembers) unless project.externalMembers.nil?
      internal_members.concat(project.internalMembers) unless project.internalMembers.nil?
    end

    uniq_external_members = external_members.uniq { |m| m.address }
    uniq_internal_members = internal_members.uniq { |m| m.address }

    return uniq_external_members, uniq_internal_members
  end

  def get_project_members(data, project_domain)
    external_members = []
    internal_members = []

    d = data.map { |hash| Hashie::Mash.new(hash) }

    d.select { |project| get_domain_from_subdomain(project.topExternalMemberDomain) == project_domain }.each do |project|
      external_members.concat(project.externalMembers) unless project.externalMembers.nil?
      internal_members.concat(project.internalMembers) unless project.internalMembers.nil?
		end

		return external_members, internal_members
	end

	def get_project_top_domain(data)
		data.map { |p| get_domain_from_subdomain(p["topExternalMemberDomain"]) }
	end

	def get_project_conversations(data, project_domain)
    # Needs to be in an array because this is how backend data is being processed in Activity.load
    # ALSO, it is now possible for multiple clusters in the data to be linked to same Account/Stream due to subdomain rollup, must collect all Conversatinos into same Stream
    data.select { |p| get_domain_from_subdomain(p["topExternalMemberDomain"]) == project_domain }
	end
end