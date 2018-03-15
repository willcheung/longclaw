include ActionView::Helpers::DateHelper  #for distance_of_time_in_words_to_now

class PlansController < ApplicationController
  layout 'empty'
  # protect_from_forgery :except => :webhook

  def index
    @subscription = Hashie::Mash.new({plan: {name: 'Basic', id: 'basic'}})
    if current_user.stripe_customer_id
      customer = Stripe::Customer.retrieve(current_user.stripe_customer_id, :expand => 'subscriptions')
      @subscription = customer.subscriptions.data.first if customer.subscriptions.data.first
    end
  end

  def new
    # check if customer already on a plan
    #redirect_to action: 'index' if current_user.pro?
    @customer = Stripe::Customer.retrieve(current_user.stripe_customer_id, :expand => 'subscriptions') if current_user.stripe_customer_id
    if @customer.present? && !@customer[:deleted] && @customer.respond_to?(:subscriptions) && @customer.subscriptions.respond_to?(:data)
      @trial_expiration_time = Time.at(@customer.subscriptions.data.first.trial_end) if @customer.subscriptions.data.first.trial_end.present?
      @subscription_expiration_time = Time.at(@customer.subscriptions.data.first.current_period_end) if @customer.subscriptions.data.first.current_period_end.present?
      @time_remaining_until_expiration_str = (@subscription_expiration_time < Time.now) ? "Expired" : (@subscription_expiration_time - Time.now < 86400 ? "< 1 day" : distance_of_time_in_words_to_now(@subscription_expiration_time)) if @subscription_expiration_time.present?
    end
  end

  def create
    token = params[:stripeToken]
    token = token == '' ? nil : token
    customer = if current_user.stripe_customer_id
                 find_or_create_customer(current_user, current_user.email, token)
               else
                 create_customer(current_user, current_user.email, token)
               end
    params.require(:plan)
    plan = params[:plan]
    raise 'invalid plan' unless Rails.configuration.stripe[:plans].include?(plan)

    if customer.subscriptions && customer.subscriptions.data.select{|s| s.plan.id}.include?(plan)
      raise "You are already subscribed to #{customer.subscriptions.data.collect{|s| s.plan.name}.join(', ')}"
    end
    subscription = Stripe::Subscription.create(
        customer: customer.id,
        items: [{plan: plan}],
        trial_period_days: Rails.configuration.stripe[:trial],
        metadata: {
            user_id: current_user.id
        }
    )
    puts "Subscription created: #{subscription}"
    logger.info "Subscription created: #{subscription}"
    current_user.upgrade(:Pro) if subscription && subscription.plan.id.start_with?('pro-') && !current_user.pro?
    current_user.upgrade(:Plus) if subscription && subscription.plan.id.start_with?('plus-') && !current_user.plus?

    if subscription && subscription.plan.id.start_with?('biz-')
      if customer.subscriptions
        existing_pro_subscription = customer.subscriptions.data.select{|s| s.plan.id.start_with?('pro-')}
        unless existing_pro_subscription.empty?
          existing_pro_subscription.each { |s| s.delete}
        end
      end
      current_user.upgrade(:Biz)
    end

    current_user.save
    if params[:refresh] == 'true'
      redirect_to :back
    elsif subscription
      redirect_to action: 'upgrade'
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
