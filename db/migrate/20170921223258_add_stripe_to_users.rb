class AddStripeToUsers < ActiveRecord::Migration
  def change
    add_column :users, :billing_email, :string
    add_column :users, :stripe_customer_id, :string

    User.where(encrypted_password: '').update_all(:role => 'Unregistered')
  end
end
