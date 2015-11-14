class UsersController < ApplicationController
  before_filter :authenticate_user!, :except => [:send_beta_teaser_email]

  def show
    @user = User.find(params[:id])
    unless @user == current_user
      redirect_to :back, :alert => "Access denied."
    end
  end

  def send_beta_teaser_email
  	@user = User.find_by_id(params[:id])
    #data = '{"id":"1483a8157a058178","subject":"Demo and training of the Alerts workflow","lastSentDate":1409331508,"contextMessages":[{"from":[{"address":"wcheung@comprehend.com","personal":"Will Cheung","encodedPersonal":"Will Cheung"}],"to":[{"address":"Lindsay.Pegg@astrazeneca.com","personal":"Pegg, Lindsay","encodedPersonal":"Pegg, Lindsay"}],"cc":[],"mimeMessageId":"<CAMcOfY78X69bQO_nP9k7XAMqMPrcs8dy8hDSCbmO528zwUNREg@mail.gmail.com>","gmailMessageId":"1481817b94304703","subject":"Demo and training of the Alerts workflow","sentDate":1409153481,"previewContent":"Next Thursday 9/4 at 7am PT works best for me. I\'ve also asked our Product Manager to listen in, as this is something brand new and there may be something that he knows more than I do. Let me know if that works for your team. Thanks, Will"},{"from":[{"address":"Lindsay.Pegg@astrazeneca.com","personal":"Pegg, Lindsay","encodedPersonal":"Pegg, Lindsay"}],"to":[{"address":"wcheung@comprehend.com","personal":"Will Cheung","encodedPersonal":"Will Cheung"}],"cc":[{"address":"lblack@comprehend.com","personal":"Lee Black","encodedPersonal":"Lee Black"}],"mimeMessageId":"<a5a2385cb48c475b89a8efdbe4c5d96b@AMSPR04MB019.eurprd04.prod.outlook.com>","gmailMessageId":"1481b46f8e8c33cc","subject":"RE: Demo and training of the Alerts workflow","sentDate":1409206909,"previewContent":"Is there absolutely anyway that the training could be done on Tuesday next week just the UAT and Themis pilot are already running behind schedule and not doing the training until Thursday will delay this further? Regards Lindsay From: Will Cheung [mailto:wcheung@comprehend.com]..."},{"from":[{"address":"Lindsay.Pegg@astrazeneca.com","personal":"Pegg, Lindsay","encodedPersonal":"Pegg, Lindsay"}],"to":[{"address":"wcheung@comprehend.com","personal":"Will Cheung","encodedPersonal":"Will Cheung"}],"cc":[{"address":"lblack@comprehend.com","personal":"Lee Black","encodedPersonal":"Lee Black"}],"mimeMessageId":"<7f70db70832e41c5833b234a373a20ba@AMSPR04MB019.eurprd04.prod.outlook.com>","gmailMessageId":"1481e2dc0f7eb81d","subject":"RE: Demo and training of the Alerts workflow","sentDate":1409255588,"previewContent":"I just wondered whether youve had a chance to look at the timing of the demo for next week. Currently more people have confirmed that they can attend on Tuesday than on Thursday. Im not in the office tomorrow and I know youre not in on Monday so please could you confirm the..."},{"from":[{"address":"Lindsay.Pegg@astrazeneca.com","personal":"Pegg, Lindsay","encodedPersonal":"Pegg, Lindsay"}],"to":[{"address":"wcheung@comprehend.com","personal":"Will Cheung","encodedPersonal":"Will Cheung"}],"cc":[{"address":"lblack@comprehend.com","personal":"Lee Black","encodedPersonal":"Lee Black"}],"mimeMessageId":"<28e11f0d682a4da5a48db302c578bd28@AMSPR04MB019.eurprd04.prod.outlook.com>","gmailMessageId":"14822b4335f30125","subject":"RE: Demo and training of the Alerts workflow","sentDate":1409331508,"previewContent":"The consensus from those in the office today is that theyd like to have the demo and training on Tuesday 3-4pm (UK time) . Regards Lindsay From: Will Cheung [mailto:wcheung@comprehend.com] Sent: 29 August 2014 01:58 To: Pegg, Lindsay Cc: Lee Black Subject: Re: Demo and training..."}]}'
    #data = '{"from":[{"address":"wcheung@comprehend.com","personal":"Will Cheung","encodedPersonal":"Will Cheung"}],"to":[{"address":"Lindsay.Pegg@astrazeneca.com","personal":"Pegg, Lindsay","encodedPersonal":"Pegg, Lindsay"}],"cc":[],"mimeMessageId":"<CAMcOfY78X69bQO_nP9k7XAMqMPrcs8dy8hDSCbmO528zwUNREg@mail.gmail.com>","gmailMessageId":"1481817b94304703","subject":"Demo and training of the Alerts workflow","sentDate":1409153481,"previewContent":"Next Thursday 9/4 at 7am PT works best for me. I\'ve also asked our Product Manager to listen in, as this is something brand new and there may be something that he knows more than I do. Let me know if that works for your team. Thanks, Will"}'
    #data = data.to_json
    data = JSON.parse(params["_json"])
    #data = JSON.parse('{"message" : "Thanks Dave, we\'ll review internally.  Looking forward to seeing you and the team!— Sent from my iPhone On Wed, Aug 27, 2014 at 6:08 AM, Branham, Dave"')
    #puts data
    ##data = JSON.parse(params.to_json)
    #data = ActiveSupport::JSON.decode(params.to_json)

  	respond_to do |format|
  		if @user
  			UserMailer.beta_teaser_email(@user, data).deliver_later

  			format.html { redirect_to('http://www.contextsmith.com') }
  			format.json { render json: @user.email, status: 'User found, sending email.'}
  		else
  			format.html { redirect_to('http://www.contextsmith.com') }
  			format.json { render json: 'User not found.', status: 'User not found. No email sent.'}
  		end
  	end
  end

end