class AddEncryptToUsersStep2 < ActiveRecord::Migration
  def change
  	User.all.each do |u|
  		if !u.plain_oauth_refresh_token.nil?
  			u.oauth_refresh_token = u.plain_oauth_refresh_token
  			u.save
  		end
  	end
  end
end
