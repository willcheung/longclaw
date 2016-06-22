require File.expand_path('../boot', __FILE__)

require 'rails/all'
require 'hashie'

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(:default, Rails.env)

module Longclaw
  class Application < Rails::Application
    config.autoload_paths += %W(#{config.root}/lib) # add modules from /lib

    # Load config file into environment 
    config.before_configuration do
        api_keys_config_file = File.join(Rails.root,'config','api_keys.yml')
        raise "#{api_keys_config_file} is missing!" unless File.exists? api_keys_config_file
        api_keys_config = YAML.load_file(api_keys_config_file)[Rails.env].symbolize_keys

        api_keys_config.each do |key, value|
            ENV[key.to_s] = value.to_s
        end # end YAML.load_file
    end

    self.configure do
        config.action_mailer.smtp_settings = {
        address:    'smtp.mandrillapp.com',
        port:       587,
        user_name:  ENV['mandrill_user_name'],
        password:   ENV['mandrill_api_key'],
        authentication:  'plain',
        domain:  'contextsmith.com',
        enable_starttls_auto: true
        }
    end

    # Settings in config/environments/* take precedence over those specified here.
    # Application configuration should go into files in config/initializers
    # -- all .rb files in that directory are automatically loaded.

    # Set Time.zone default to the specified zone and make Active Record auto-convert to this zone.
    # Run "rake -D time" for a list of tasks for finding time zone names. Default is UTC.
    # config.time_zone = 'Central Time (US & Canada)'

    # The default locale is :en and all translations from config/locales/*.rb,yml are auto loaded.
    # config.i18n.load_path += Dir[Rails.root.join('my', 'locales', '*.{rb,yml}').to_s]
    # config.i18n.default_locale = :de

    config.action_dispatch.default_headers['X-Frame-Options'] = "ALLOW-FROM na30.salesforce.com"

    require 'contextsmith_parser'
    require 'utils'
  end
end
