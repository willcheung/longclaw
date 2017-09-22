class AddStripeToUsers < ActiveRecord::Migration
  def change
    add_column :users, :billing_email, :string
    add_column :users, :stripe_customer_id, :string
  end
end
