
require "google_drive"

puts "...\n...\n\nRunning Script\n\n...\n..."


session = GoogleDrive::Session.from_config("config.json")

s = session.spreadsheet_by_key("1SmRAEWOIy_vpzyrfQhdJJvM8wVSgukpCWeU7_V_TiNk").worksheets[0]

def deleteAccount(name)
  Account.find_by_name(name).destroy
  puts "destroyed account with the name " + name
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

ActiveRecord::Base.transaction do
# Gets content of A2 cell.
  name = s[3, 2].to_s
  j = 3

  while !name.empty?
    owner = User.find_by_email(s[j, 3])

    if s[j, 1].downcase == "delete"
      deleteAccount(find_by_name)
    else
      createAccount(owner, name)
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

