require "google_drive"

puts "...\n...\n\nRunning Script\n\n...\n..."


session = GoogleDrive::Session.from_config("config.json")

s = session.spreadsheet_by_key("1zY5KYcFDIPaau2l1i57UukId2ahm495bGhf3X-Y_WnM").worksheets[0]

def createProject(account, name, owner)
    account_id = account.id

    p = Project.new(name: name,
                    owner_id: owner.id,
                    created_by: owner.id,
                    updated_by: owner.id,
                    created_at: Time.now,
                    updated_at: Time.now,
                    is_confirmed: true,
                    category: "Opportunity",
                    account_id: account_id)
    p.save(validate: false)
    puts "created Project with name: "+ name
  end

  def deleteProject(name)
    p = Project.find_by_name(name).destroy
    puts "destroyed Project with name: " + name
  end

ActiveRecord::Base.transaction do
# Gets content of A2 cell.
  name = s[3, 2].to_s
  j = 3
  while !name.empty?
    owner = User.find_by_email(s[j, 4])
    account = Account.find_by_name(s[j,3])

    
    if s[j, 1].downcase == "delete"
      deleteProject(name)
    elsif s[j, 1].downcase == "create"
      createProject(account, name, owner)
    else 
      p "no task assigned to row: " + j
    end





    j += 1
    name = s[j, 2].to_s
  end

end

#puts ws[1,1]  #==> "hoge"

# Changes content of cells.
# Changes are not sent to the server until you call ws.save().
#ws[2, 1] = "foo"
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

