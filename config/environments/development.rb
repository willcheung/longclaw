Longclaw::Application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # In the development environment your application's code is reloaded on
  # every request. This slows down response time but is perfect for development
  # since you don't have to restart the web server when you make code changes.
  config.cache_classes = false

  # Do not eager load code on boot.
  config.eager_load = false

  # Show full error reports and disable caching.
  config.consider_all_requests_local       = true
  config.action_controller.perform_caching = true
  config.cache_store = :memory_store
  # config.cache_store = :redis_store, {
  #   expires_in: 30.minutes,
  #   namespace: 'cache',
  #   redis: { host: 'localhost', port: 6379, db: 0 },
  # }

  # Don't care if the mailer can't send.
  config.action_mailer.raise_delivery_errors = true

  # Use letter_opener to preview e-mail
  config.action_mailer.delivery_method = :letter_opener

  # Print deprecation notices to the Rails logger.
  config.active_support.deprecation = :log

  # Raise an error on page load if there are pending migrations
  config.active_record.migration_error = :page_load


  # Debug mode disables concatenation and preprocessing of assets.
  # This option may cause significant delays in view rendering with a large
  # number of complex assets.
  config.assets.debug = true
end
