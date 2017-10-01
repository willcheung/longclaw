Rails.configuration.stripe = {
    publishable_key: ENV['STRIPE_PUBLIC_KEY'] || 'pk_test_tD2OOTfbs9k93ftj3Lx9KWYX',
    secret_key: ENV['STRIPE_SECRET_KEY'] || 'sk_test_PvExPsOgID5mEUyPnVa2U0RF', # test key
    plans: ['pro-v1', 'pro-monthly-v1','biz-v1', 'biz-monthly-v1'],
    trial: ENV['STRIPE_PLAN_TRIAL'] ? ENV['STRIPE_PLAN_TRIAL'].to_i : 14
}

Stripe.api_key = Rails.configuration.stripe[:secret_key]
