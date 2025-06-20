require('uglifier')
Longclaw::Application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.cache_classes = true

  # Eager load code on boot. This eager loads most of Rails and
  # your application in memory, allowing both thread web servers
  # and those relying on copy on write to perform better.
  # Rake tasks automatically ignore this option for performance.
  config.eager_load = true

  # Full error reports are disabled and caching is turned on.
  config.consider_all_requests_local       = false
  config.action_controller.perform_caching = true

  # Enable Rack::Cache to put a simple HTTP cache in front of your application
  # Add `rack-cache` to your Gemfile before enabling this.
  # For large-scale production use, consider using a caching reverse proxy like nginx, varnish or squid.
  # config.action_dispatch.rack_cache = true

  # Disable Rails's static asset server (Apache or nginx will already do this).
  config.serve_static_files = false

  # Compress JavaScripts and CSS.
  config.assets.js_compressor = Uglifier.new(harmony: true)
  # config.assets.css_compressor = :sass

  # Do not fallback to assets pipeline if a precompiled asset is missed.
  config.assets.compile = true

  # Generate digests for assets URLs.
  config.assets.digest = true

  # Version of your assets, change this if you want to expire all your assets.
  config.assets.version = '1.0'

  # Specifies the header that your server uses for sending files.
  # config.action_dispatch.x_sendfile_header = "X-Sendfile" # for apache
  # config.action_dispatch.x_sendfile_header = 'X-Accel-Redirect' # for nginx

  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  config.force_ssl = true
  config.ssl_options = {  exclude: proc { |env| env['PATH_INFO'] =~ /healthcheck/} }

  # Set to :debug to see everything in the log.
  config.log_level = :debug
  config.active_record.logger = nil

  # Prepend all log lines with the following tags.
  # config.log_tags = [ :subdomain, :uuid ]

  # Use a different logger for distributed setups.
  # config.logger = ActiveSupport::TaggedLogging.new(SyslogLogger.new)

  # Use a different cache store in production.
  config.cache_store = :redis_store, {
    expires_in: 30.minutes,
    namespace: 'cache',
    redis: { host: 'longclaw-cache.f1j5bl.0001.usw2.cache.amazonaws.com', port: 6379, db: 0 },
  }

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.action_controller.asset_host = "http://assets.example.com"

  # Precompile additional assets.
  # application.js, application.css, and all non-JS/CSS in app/assets folder are already added.

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation can not be found).
  config.i18n.fallbacks = true

  # Send deprecation notices to registered listeners.
  config.active_support.deprecation = :notify

  # Disable automatic flushing of the log to improve performance.
  # config.autoflush_log = false

  # Use default logging formatter so that PID and timestamp are not suppressed.
  config.log_formatter = ::Logger::Formatter.new

  config.action_mailer.delivery_method = :smtp
  config.action_mailer.perform_deliveries = true
  config.action_mailer.logger = nil
  # Ignore bad e-mail addresses and do not raise e-mail delivery errors.
  # Set this to true and configure the e-mail server for immediate delivery to raise delivery errors.
  config.action_mailer.raise_delivery_errors = true

  Rails.application.config.middleware.use ExceptionNotification::Rack,
  :email => {
    :email_prefix => "[ERROR] ",
    :sender_address => %{"ContextSmith Notifications" <notifications@contextsmith.com>},
    :exception_recipients => %w{support@contextsmith.com}
  },
  :slack => {
    :webhook_url => "https://hooks.slack.com/services/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",
    :channel => "#server_errors",
    :additional_parameters => {
      :mrkdwn => true
    }
  }
end
