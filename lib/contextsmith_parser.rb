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
    # should only try to extract members from one project
    d = data.map { |hash| Hashie::Mash.new(hash) }
    project = d.find { |proj| proj.topExternalMemberDomain == project_domain }

    external_members = project.externalMembers if project.present? || []
    internal_members = project.internalMembers if project.present? || []

		return external_members, internal_members
  end

	def get_project_top_domain(data)
		data.map { |p| p["topExternalMemberDomain"] }
	end

	def get_project_conversations(data, project_domain)
    # Needs to be in an array because this is how backend data is being processed in Activity.load
    # should only select at most one project, returns => [project] or []
    data.select { |p| p["topExternalMemberDomain"] == project_domain }
	end
end