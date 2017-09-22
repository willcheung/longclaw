class PlansController < ApplicationController
  layout 'empty'

  def index

  end

  def new
    # check if customer already on a plan
    redirect_to action: 'index' if current_user.pro?
  end

  def create
    redirect_to action: 'index' if current_user.pro? # don't create subscription if user already is pro

    customer = if current_user.stripe_customer_id
                 find_or_create_customer(current_user, params[:stripeEmail], params[:stripeToken])
               else
                 create_customer(current_user, params[:stripeEmail], params[:stripeToken])
               end

    subscription = Stripe::Subscription.create(
      customer: customer.id,
      items: [{ plan: Rails.configuration.stripe.plans.pro }],
      trial_period_days: Rails.configuration.stripe.trial,
      metadata: {
        user_id: current_user.id
      }
    )
    puts "Subscription created: #{subscription}"
    logger.info "Subscription created: #{subscription}"
    current_user.upgrade(:Pro) if subscription
    current_user.save
  rescue Stripe::StripeError => e
    logger.error e
    flash[:error] = e.message
    redirect_to new_plan_path
  end

  private

  def find_or_create_customer(user, stripe_email, source)
    customer = Stripe::Customer.retrieve(user.stripe_customer_id)
    customer[:deleted] ? create_customer(user, stripe_email, source) : customer
  rescue Stripe::StripeError => e
    if e.http_status == 404
      # can't find the customer, create a new one
      create_customer(user, stripe_email, source)
    else
      raise e
    end
  end

  def create_customer(user, stripe_email, source)
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
