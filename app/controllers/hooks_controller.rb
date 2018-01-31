class HooksController < ApplicationController

  def jira
    data = Hashie::Mash.new(JSON.parse(request.body.read))
    user = User.find_by_email(data.user.emailAddress)
    user_id = user ? user.id : '00000000-0000-0000-0000-000000000000'
    # current Opportunity finding algorithm is very limited. This SHOULD be improved in the future!
    project = Project.visible_to(user.organization_id, user.id).find_by_name(data.issue.fields.project.name)
    project_id = project ? project.id : '00000000-0000-0000-0000-000000000000'
    from_data = data.issue.fields.reporter ? [{ address: data.issue.fields.reporter.emailAddress, personal: data.issue.fields.reporter.displayName }] : []
    to_data = data.issue.fields.assignee ? [{ address: data.issue.fields.assignee.emailAddress, personal: data.issue.fields.assignee.displayName }] : []
    cc_data = data.issue.fields.creator ? [{ address: data.issue.fields.creator.emailAddress, personal: data.issue.fields.creator.displayName }] : []
    jira = Activity.find_or_initialize_by(
      category: Activity::CATEGORY[:JIRA],
      backend_id: data.issue.id
    )
    jira.update(
      title: data.issue.fields.summary,
      note: data.issue.fields.description,
      last_sent_date: Time.at(data.timestamp/1000).utc,
      last_sent_date_epoch: data.timestamp/1000,
      from: from_data,
      to: to_data,
      cc: cc_data,
      email_messages: [data],
      posted_by: user_id,
      project_id: project_id
    )

    render nothing: true
  end

  def zendesk
    data = Hashie::Mash.new(JSON.parse(request.body.read))
    user = User.find_by_email(data.current_user.address)
    user_id = user ? user.id : '00000000-0000-0000-0000-000000000000'
    # current Opportunity finding algorithm is very limited. This SHOULD be improved in the future!
    visible_accounts = Account.visible_to(user)
    account = visible_accounts.find_by_name(data.organization) || visible_accounts.find_by_domain(get_domain(data.requester.first.address))
    project_id = account.present? && account.projects.present? ? account.projects.first.id : '00000000-0000-0000-0000-000000000000'
    assignee = data.assignee.first.address.present? ? data.assignee : []
    zd = Activity.find_or_initialize_by(
      category: Activity::CATEGORY[:Zendesk],
      backend_id: data.id
    )
    zd.update(
      title: data.title,
      note: data.comments.last.text,
      last_sent_date: data.updated_at.to_time.utc,
      last_sent_date_epoch: data.updated_at.to_time.to_i,
      from: data.requester,
      to: assignee,
      cc: data.cc,
      email_messages: [data],
      posted_by: user_id,
      project_id: project_id
    )

    render nothing: true
  end

  def fullcontact_person
    data = Hashie::Mash.new(JSON.parse(request.body.read))
    data.webhookId = JSON.parse(data.webhookId)
    profile = Profile.find_by_id(data.webhookId.id) || Profile.find_by_email(data.webhookId.email)
    if profile.present?
      profile.update(data: data.result)
    else
      puts "** Caution: FullContact webhook tried to update a Profile with id=#{data.webhookId.id} or email=#{data.webhookId.email}, but it could not be found! **"
    end

    render nothing: true
  end

  def fullcontact_company_v2
    data = Hashie::Mash.new(JSON.parse(request.body.read))
    data.webhookId = JSON.parse(data.webhookId)
    company = CompanyProfile.find_by_id(data.webhookId.id) || CompanyProfile.find_by_domain(data.webhookId.domain)
    if company.present?
      company.update(data: data.result)
    else
      puts "** Caution: FullContact webhook tried to update a CompanyProfile with id=#{data.webhookId.id} or domain=#{data.webhookId.domain}, but it could not be found! **"
    end

    render nothing: true
  end

  def fullcontact_company_v3
    data = Hashie::Mash.new(JSON.parse(request.body.read))
    # data.webhookId = JSON.parse(data.webhookId)
    company = CompanyProfile.find_by_id(params['id']) || CompanyProfile.find_by_domain(params['domain'])
    if company.present?
      data.result.status = 200 unless data.result.status?
      company.update(data: data.result)
    else
      puts "** Caution: FullContact webhook tried to update a CompanyProfile with id=#{params['id']} or domain=#{params['domain']}, but it could not be found! **"
    end

    render nothing: true
  end

  def load_emails_since_yesterday
    LoadEmailsSinceYesterdayJob.perform_later

    render nothing: true
  end

  def load_events_since_yesterday
    LoadEventsSinceYesterdayJob.perform_later

    render nothing: true
  end

  alias_method :fullcontact_company, :fullcontact_company_v3

end
