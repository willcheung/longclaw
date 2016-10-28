class HooksController < ApplicationController

  def jira
    data = Hashie::Mash.new(JSON.parse(request.body.read))
    user = User.find_by_email(data.user.emailAddress)
    if user
      project = Project.visible_to(user.organization.id, user.id).find_by_name(data.issue.fields.project.name)
      if project
        jira = project.activities.find_or_initialize_by(
          category: Activity::CATEGORY[:JIRA],
          backend_id: data.issue.id
        )
        from_data = data.issue.fields.reporter ? [{ address: data.issue.fields.reporter.emailAddress, personal: data.issue.fields.reporter.displayName }] : []
        to_data = data.issue.fields.assignee ? [{ address: data.issue.fields.assignee.emailAddress, personal: data.issue.fields.assignee.displayName }] : []
        cc_data = data.issue.fields.creator ? [{ address: data.issue.fields.creator.emailAddress, personal: data.issue.fields.creator.displayName }] : []
        jira.update(
          title: data.issue.fields.summary,
          note: data.issue.fields.description,
          last_sent_date: Time.at(data.timestamp/1000).utc,
          last_sent_date_epoch: data.timestamp/1000,
          from: from_data,
          to: to_data,
          cc: cc_data,
          email_messages: [data],
          posted_by: user.id
        )
      end
    end

    render nothing: true
  end

end