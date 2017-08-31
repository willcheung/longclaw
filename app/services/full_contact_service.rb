
class FullContactService

  # Call the FullContact API to find a person by email and returns the response
  # if data not found in FullContact's cache, another call is made to register a webhook so an update is pushed to us when data is available
  def self.find(email, profile_id)
    res = FullContact.person(email: email)
    # not found in FullContact cache, register a webhoook to send the info back to us when it is available
    FullContact.person(email: email, webhookUrl: ENV['BASE_URL'] + '/hooks/fullcontact', webhookBody: 'json', webhookId: { email: email, id: profile_id }.to_json) if res.status == 202
    res
  rescue => e
    puts "Request to FullContact API FAILED: #{e.inspect}"
    { status: e.to_s[-3..-1].to_i, exception: e }
  end

end