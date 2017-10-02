require "google_drive"

puts "...\n...\n\nRunning Script\n\n...\n..."

session = GoogleDrive::Session.from_config("config.json")

s = session.spreadsheet_by_key("1hGczRmZvn9ichUFcsNrdRNG6rZ35ZkzcsfmbTXFzlLY").worksheets[0]

def create_to_hash(receiver)
  toHash = [{:personal => receiver.first_name, :address => receiver.email}]
end

def create_from_hash(sender)
  fromHash = [{:personal => sender.first_name, :address => sender.email}]
end

def create_message( subject, body, toArray, fromArray, attachmentHash, dateTime)
    

    contentHash = { :body => body,
                    :salutation =>"Thanks, Collin",
                    :signature => "Collin"}
    messageHash = {    :from => fromArray,
                        :content => contentHash,
                        :to => toArray, 
                        :sentDate => dateTime.to_i, 
                        :isPrivate => false, 
                        :sourceInboxes => [fromArray[0]['address']], 
                        :subject => subject}
    messageHash[:attachments] = attachmentHash if attachmentHash
    return messageHash
end

def create_conversation(title, dateTime, messageArray, toArray, fromArray, project, senderID)
    category = "Conversation"
    title = title
=begin
    if attachment
      messagehash[0].attachment = attachment
    end
=end

    email = Activity.new( category: category,
                          title: title,
                          is_public: true,
                          from: fromArray,
                          to: toArray,
                          cc: {},
                          last_sent_date: dateTime,
                          email_messages: messageArray,
                          project_id: project.id,
                          posted_by: senderID,
                          created_at: dateTime,
                          updated_at: dateTime,
                          last_sent_date_epoch: dateTime.to_i
                          )
    email.save(validate:false)
    puts "created email with title: " + title
  end

  def to_mimeType(name)
    if name.split('.')[1] == "png"
      return "image/png"
    end
  end

  def to_attachment_hash (attachments)
    if attachments
      newAttachment = attachments.split(',').map { |e| { urn: "urn:blank",
                                        name: e,
                                        mimeType: to_mimeType(e)
                                        }  }
      return newAttachment
    end
    return null


  end

  def delete_email(email)
    email.destroy
    puts(" destroyed email with the title: "+email.title)
  end
ActiveRecord::Base.transaction do
# Gets content of cell.
  title = s[3, 2].to_s
  j = 3
#conversation array
  conversations = []

  while !title.empty? #mapping all the fields to variables
    sender = User.find_by_email(s[j, 5])
    receiver = User.find_by_email(s[j, 6])
    dateTime = DateTime.parse(s[j, 3])
    subject = s[j,8].to_s
    body = s[j,9].to_s
    title = s[j,2].to_s
    attachmentHash = to_attachment_hash(s[j,10])
    p = Project.find_by_name(s[j,7])
    convNum = s[j,11]

#grabbing action for field
    if s[j, 1].downcase == "delete"
      delete_email(Activity.find_by_title(s[j,2]))
    elsif s[j, 1].downcase == "create"
      toArray = create_to_hash(receiver)
      fromArray = create_from_hash(sender)
      messageHash = create_message(subject, body, toArray, fromArray, attachmentHash, dateTime)
      visited = false
      activity = [toArray, fromArray, messageHash, title, dateTime, convNum, p, sender.id]
    else 
      puts "no task assigned to row: " + j
    end

    conversations.push(activity)
    j += 1
    title = s[j, 2].to_s
  end
#sorting coversations by conversation # to see if they are to be put in same conversation
  conversations.sort! {|x, y| x[5] <=> y[5]} 
  i=0
  j = 0
  while i != conversations.size
    if i == conversations.size-1
      convRange = conversations[j..i]
      messageArray=[]
      convRange.each{ |e|
        messageArray.push(e[2])
      }
      create_conversation(convRange.last[3], convRange.last[4], messageArray, convRange.last[0], convRange.last[1], convRange.last[6], convRange.last[7])

    elsif(conversations[i][5] == conversations[i+1][5])

    else
      convRange = conversations[j..i]
      messageArray=[]
      convRange.each{ |e|
        messageArray.push(e[2])
      }
      create_conversation(convRange.last[3], convRange.last[4], messageArray, convRange.last[0], convRange.last[1], convRange.last[6], convRange.last[7])
      j = i+1
    end
    i = i+1
    puts i
  end
end
#ws[2, 2] = "bar"
#ws.save

# Dumps all cells.
#(1..ws.num_rows).each do |row|
 # (1..ws.num_cols).each do |col|
  #  p ws[row, col]
  #end
#end

# Yet another way to do so.
#p ws.rows  #==> [["fuga", ""], ["foo", "bar]]

# Reloads the worksheet to get changes by other clients.
#ws.reload