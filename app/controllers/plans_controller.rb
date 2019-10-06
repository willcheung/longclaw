include ActionView::Helpers::DateHelper  #for distance_of_time_in_words_to_now
require "stripe"

class PlansController < ApplicationController
  layout 'empty'
  # protect_from_forgery :except => :webhook

  def index
    # TEST upgrading/downgrading
    #current_user.downgrade!
    #current_user.upgrade(:Plus)

    UserMailer.weekly_tracking_summary(current_user).deliver_later

    if current_user.stripe_customer_id
      customer = Stripe::Customer.retrieve(current_user.stripe_customer_id, :expand => 'subscriptions')
      @subscription = customer.subscriptions.first if customer.subscriptions.first
    else
      @subscription = Hashie::Mash.new({plan: {name: 'Basic', id: 'basic'}})
    end
  end

  def new
    # check if user is logged in
    return if current_user.nil?

    # check Stripe subscription
    @customer = Stripe::Customer.retrieve(current_user.stripe_customer_id, :expand => 'subscriptions') if current_user.stripe_customer_id
    if @customer.present? && !@customer[:deleted] && @customer.respond_to?(:subscriptions) && @customer.subscriptions.respond_to?(:data) && !@customer.subscriptions.data.empty?
      @trial_expiration_time = Time.at(@customer.subscriptions.data.first.trial_end) if @customer.subscriptions.data.first.trial_end.present?
      @subscription_expiration_time = Time.at(@customer.subscriptions.data.first.current_period_end) if @customer.subscriptions.data.first.current_period_end.present?
      @time_remaining_until_expiration_str = (@subscription_expiration_time < Time.now) ? "Expired" : (@subscription_expiration_time - Time.now < 86400 ? "less than 1 day" : distance_of_time_in_words_to_now(@subscription_expiration_time)) if @subscription_expiration_time.present?  # any time of 1 day or less (but still any) will be displayed as "less than 1 day"
    end

  end

  def create

    token = params[:stripeToken]
    token = token == '' ? nil : token

    # Get Stripe customer
    customer = if current_user.stripe_customer_id
                 find_or_create_customer(current_user, current_user.email, token)
               else
                 create_customer(current_user, current_user.email, token)
               end

  # Update customer's payment source
    if !token.blank?
      Stripe::Customer.create_source(
        customer.id,
        {
          source: token,
        }
      )
      logger.info "Updated payment method for #{current_user.email}"
    end

    params.require(:plan)
    plan = params[:plan]
    raise 'Invalid plan! Please try again.' unless Rails.configuration.stripe[:plans].include?(plan)

    if customer.subscriptions.present? && customer.subscriptions.data.present? && customer.subscriptions.first.status != 'canceled'
      logger.info "Subscription exists #{customer.subscriptions.data.collect{|s| s.plan.nickname}.join(', ')}"

      # If in the middle of a trial
      if !customer.subscriptions.data.first.trial_end.nil? and Time.at(customer.subscriptions.data.first.trial_end) > Time.now
        logger.info "In middle of trial. Ending it now to trigger charge/invoice."
        # End trial, which will trigger charge/invoice
        # https://stripe.com/docs/billing/subscriptions/trials
        # TODO: What if they selected another plan? Need to handle...
        subscription = Stripe::Subscription.update(
          customer.subscriptions.first.id,
          {
            trial_end: 'now',
          }
        )
      else # If trial expired and/or cc payment failed, subscription has 2 states.  "past_due" and "unpaid"
        if customer.subscriptions.first.status == 'active' and customer.subscriptions.first.plan == plan
          # Same plan, nothing to do!
          logger.info "On active subscription.  Nothing to do!"
          raise "<p>You're on a paid plan! </p> <p>You can also click \"Purchase\" to select a new plan.</p>".html_safe # happy state, do nothing
        elsif customer.subscriptions.first.status == 'active' and customer.subscriptions.first.plan != plan
          # Update plan if different from current plan
          logger.info "Updating plan to #{plan}!"

          subscription = Stripe::Subscription.update(
              customer.subscriptions.first.id,
              {
                cancel_at_period_end: false,
                items: [
                  {
                    id: customer.subscriptions.first.items.data[0].id,
                    plan: plan
                  }
                ],
              }
            )
        elsif customer.subscriptions.first.status == 'past_due' || customer.subscriptions.first.status == 'unpaid'
          # Find latest invoice, its period end date and calculate prorated for next invoice
          invoice = Stripe::Invoice.retrieve(customer.subscriptions.first.latest_invoice)
          invoice_period_end = invoice.lines.data.first.period.end
          invoice.void_invoice

          # Determine which subscription they're on
          if customer.subscriptions.first.plan.id.start_with?('pro-')
            amt = 2500
          elsif customer.subscriptions.first.plan.id.start_with?('plus-')
            amt = 500
          else
            amt = 500
          end

          Stripe::InvoiceItem.create({
              customer: customer,
              currency: 'usd',
              amount: (((invoice_period_end.to_f - Time.now.to_f)/(31*24*60*60))*amt).to_i,
              subscription: customer.subscriptions.first,
              description: 'ContextSmith Plus prorated',
              period: { end: invoice_period_end, start: Time.now.to_i }
          })

          logger.info "Created prorated invoice item."

        else # should never come here
          logger.info "Subscription in a weird state.  Nothing to do!"
          raise "Nothing to do!"
        end
      end

      flash[:notice] = "Thank you for subscribing to ContextSmith!"
    else
      # Creates new subscription with 14 day trial
      subscription = Stripe::Subscription.create(
          customer: customer,
          items: [{plan: plan}],
          trial_period_days: Rails.configuration.stripe[:trial],
          metadata: {
              user_id: current_user.id
          }
      )
      logger.info "Subscription created: #{subscription}"

      flash[:notice] = "Great, enjoy our free trial!"
    end

    # Update ContextSmith user
    logger.info "New subscription plan: #{subscription.plan.id}"
    if subscription.plan.id.start_with?('pro-')
      current_user.upgrade(:Pro)
      logger.info "Changing user to Pro"
    elsif subscription.plan.id.start_with?('plus-')
      current_user.upgrade(:Plus)
      logger.info "Changing user to Plus"
    else
      raise "Invalid plan! Please try again."
    end

    current_user.save

    if params[:refresh] == 'true'
      redirect_to :back
    elsif subscription
      redirect_to new_plan_path
    end
  rescue RuntimeError, Stripe::StripeError => e
    logger.error e
    flash[:error] = e.message
    redirect_to new_plan_path
    return
  end

  def upgrade
    # sign_out current_user
    customer = Stripe::Customer.retrieve(current_user.stripe_customer_id, expand: 'subscriptions')
    if customer.subscriptions.data
      @sub = customer.subscriptions.data[0]
      @trial_end = Time.at(@sub.trial_end)
    end
  end


  private

  def find_or_create_customer(user, stripe_email, source)
    customer = Stripe::Customer.retrieve(user.stripe_customer_id, :expand => 'subscriptions')
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
