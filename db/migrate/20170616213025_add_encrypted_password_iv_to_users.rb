class AddEncryptedPasswordIvToUsers < ActiveRecord::Migration
  def change
    add_column :users, :encrypted_password_iv, :string

    ### This is what the code should be for encrypting/decrypting along with the migration
    ### For some reason, decrypting when rolling back ("down") works, but encrypting when migrating ("up") does not work
    ### If needed, you can run the equivalent of these in rails console manually
    # reversible do |dir|
    #   dir.up do
    #     # encrypt all passwords for exchange users using attr_encrypted
    #     puts "encrypting passwords..."
    #     User.reset_column_information
    #     User.exchange_auth.each do |u|
    #       plaintext_pwd = u.encrypted_password
    #       u.encrypted_password = '' # need to reset to empty string here or else attr_encrypted will throw error when trying to set password
    #       u.password = plaintext_pwd
    #       u.save
    #     end
    #   end
    #   dir.down do
    #     # decrypt all passwords for exchange users using attr_encrypted
    #     puts "decrypting passwords..."
    #     User.exchange_auth.each do |u|
    #       u.encrypted_password = u.password
    #       u.encrypted_password_iv = nil
    #       u.save
    #     end
    #   end
    # end
  end
end
