require 'friendly_code'

class PlansService

  # Upgrade a user or add trial days because of a referral
  def self.referral(code)
    puts "Referral code #{code} used"
    bonus = Rails.configuration.stripe[:bonus]
    user = referral_user(code)
    unless user.nil?
      customer = if user.stripe_customer_id
                   find_or_create_customer(user, user.email)
                 else
                   create_customer(current_user, current_user.email)
                 end
      customer[:account_balance] -= bonus
      customer.save
      puts "Referral from #{user.email}. Credited #{bonus} cents to Stripe ID #{customer.id}"
    end
  end

  # create or retrieve referral code for current user
  def self.referral_code(user)
    ts = TrackingSetting.find_or_create(user)
    create_referral_code(ts) if ts.referral.nil?
    ts.referral
  end

  # find the user belonging to the referral code
  def self.referral_user(code)
    ts = TrackingSetting.find_by_referral(code)
    ts.user unless ts.nil?
  end

  def self.create_referral_code(ts)
    ts.referral = FriendlyCode.generate(8)
    ts.save
  end

  def self.find_or_create_customer(user, stripe_email, source: nil)
    customer = Stripe::Customer.retrieve(user.stripe_customer_id, :expand => 'subscriptions')
    customer[:deleted] ? create_customer(user, stripe_email, source) : customer
  rescue Stripe::StripeError => e
    if e.http_status == 404
      # can't find the customer, create a new one
      create_customer(user, stripe_email, source)
    else
      raise e
    end
  end

  def self.create_customer(user, stripe_email, source: nil)
    customer = Stripe::Customer.create(
      email: stripe_email,
      metadata: { user_id: user.id },
      source: source
    )
    user.billing_email = stripe_email
    user.stripe_customer_id = customer.id
    user.save
    customer
  end
end