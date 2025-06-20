class DeviseCreateUsers < ActiveRecord::Migration
  def change
    create_table :users, id: :uuid do |t|
      ## Database authenticatable
      t.string :first_name,         null: false, default: ""
      t.string :last_name,          null: false, default: ""
      t.string :email,              null: false, default: ""
      t.string :encrypted_password, null: false, default: ""
      t.string :image_url

      ## Recoverable
      t.string   :reset_password_token
      t.datetime :reset_password_sent_at

      ## Rememberable
      t.datetime :remember_created_at

      ## Trackable
      t.integer  :sign_in_count, default: 0, null: false
      t.datetime :current_sign_in_at
      t.datetime :last_sign_in_at
      t.inet     :current_sign_in_ip
      t.inet     :last_sign_in_ip

      ## Confirmable
      # t.string   :confirmation_token
      # t.datetime :confirmed_at
      # t.datetime :confirmation_sent_at
      # t.string   :unconfirmed_email # Only if using reconfirmable

      ## Lockable
      # t.integer  :failed_attempts, default: 0, null: false # Only if lock strategy is :failed_attempts
      # t.string   :unlock_token # Only if unlock strategy is :email or :both
      # t.datetime :locked_at

      ## OAuth
      t.string  :oauth_provider
      t.string  :oauth_provider_uid
      t.string  :oauth_access_token
      t.string  :oauth_refresh_token
      t.datetime  :oauth_expires_at

      # Organization foreign key
      t.uuid    :organization_id

      # Others
      t.string :department
      t.integer :hourly_rate
      t.boolean :is_billable

      t.timestamps
    end

    add_index :users, :email,                unique: true
    add_index :users, :reset_password_token, unique: true
    # add_index :users, :confirmation_token,   unique: true
    # add_index :users, :unlock_token,         unique: true
  end
end
