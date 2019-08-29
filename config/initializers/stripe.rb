Rails.configuration.stripe = {
    publishable_key: ENV['STRIPE_PUBLIC_KEY'] || 'pk_test_tD2OOTfbs9k93ftj3Lx9KWYX',
    secret_key: ENV['STRIPE_SECRET_KEY'] || 'sk_test_PvExPsOgID5mEUyPnVa2U0RF', # test key
    plans: ['pro-monthly-v2', 'plus-monthly-v1'],
    trial: 14,
    bonus: 500 # in cents
}

Stripe.api_key = Rails.configuration.stripe[:secret_key]
