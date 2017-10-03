# new columns to tie subscriptions to stripe plans. Also, if stripe is not used plan_id is consulted to auto-upgrade users
class AddStripeToOrganization < ActiveRecord::Migration
  def change
    add_column :organizations, :billing_email, :string
    add_column :organizations, :stripe_customer_id, :string
    add_column :organizations, :plan_id, :string
  end
end
