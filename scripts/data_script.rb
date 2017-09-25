
puts "...\n...\n\nRunning Script\n\n...\n..."

  def createUser (first_name, last_name, email)
      user = User.new
      user.first_name =  first_name
      user.last_name =  last_name
      user.email = email
      user.save(validate: false)
      puts "created user with name " + first_name + " " + last_name
  end

  def deleteUser(id)
        u = User.find_by_id(id)
        u.destroy
  end

  def createAccount(user, name)
        owner_id = user.id
        domain = 'example.com'
        organization_id = Organization.find_by_domain("contextsmith.com").id
        account = Account.new(domain: domain,
                              name: name,
                              category: Account::CATEGORY[:Customer],
                              website: 'http://www.example.com',
                              owner_id: owner_id,
                              organization_id: organization_id,
                              created_by: owner_id)
        account.save(validate: false)
        puts "created account with name: " + name 
  end

  def deleteAccount(name)
      a = Account.find_by_name(name)
      a.destroy
  end

  def createProject(account, name, owner)
    account_id = account.id

    p = Project.new(name: name,
                    owner_id: owner.id,
                    created_by: owner.id,
                    updated_by: owner.id,
                    created_at: Time.now,
                    updated_at: Time.now,
                    is_confirmed: true,
                    account_id: account_id)
    p.save(validate: false)
  end

  def createUserAToZ
    letters = ('A'..'Z').to_a
    while letters.first != 'Z'
      i = letters.shift 
      createUser(i, i + i, i+"@gmail.com")
    end
  end

  def deleteUserAToZ
    letters = ('A'..'Z').to_a
    while letters.first != 'Z'
      i = letters.shift 
      user = User.find_by_email(i + "@gmail.com")
      deleteUser(user.id)
    end
  end

  def createAccountAToZ
    letters = ('A'..'Z').to_a
    while letters.first != 'Z'
      i = letters.shift
      user = User.find_by_email(i + "@gmail.com")
      createAccount(user, i)
    end
  end

  def deleteAccountAToZ
    letters = ('A'..'Z').to_a
      while letters.first != 'Z'
        i = letters.shift
        user = User.find_by_email(i + "@gmail.com")
        puts "found " + user.email
        deleteAccount(user)
      end
  end

  def createEmail(sender, receiver, project)
    category = "Conversation"
    title = "Test Title"
    fromhash = [{:personal => sender.first_name, :address => sender.email}]
    fromarray = {:personal => sender.first_name, :address => sender.email}
    #from = JSON.parse(fromhash) #=> "{\"hello\":\"goodbye\"}"
    tohash = [{:personal => receiver.first_name, :address => receiver.email}]
    toarray = {:personal => receiver.first_name, :address => receiver.email}
    #to = JSON.parse(tohash) #=> "{\"hello\":\"goodbye\"}"
    contenthash = {:body => "See you this afternoon at 999999!\n\nBest,",
                    :salutation =>"cool,",
                    :signature => "Collin"}
    messagehash = [{ :from => fromhash,
                        :content => contenthash,
                        :to => tohash, 
                        :sentDate => Time.now.to_i, 
                        :isPrivate => false, 
                        :sourceInboxes => [sender.email], 
                        :subject => "Looking forward to our meeting this afternoon"}]
    #message = JSON.parse(messagehash)
    email = Activity.new( category: category,
                          title: title,
                          is_public: true,
                          from: fromhash,
                          to: tohash,
                          cc: {},
                          last_sent_date: Time.now,
                          email_messages: messagehash,
                          project_id: project.id,
                          posted_by: sender.id,
                          created_at: Time.now,
                          updated_at: Time.now,
                          last_sent_date_epoch: Time.now.to_i
                          )
    email.save(validate:false)
  end

ActiveRecord::Base.transaction do



  
end

