class HooksController < ApplicationController

  def jira
    data = Hashie::Mash.new(JSON.parse(request.body.read))
    user = User.find_by_email(data.user.emailAddress)
    user_id = user ? user.id : '00000000-0000-0000-0000-000000000000'
    project = Project.find_by_name(data.issue.fields.project.name)
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

end