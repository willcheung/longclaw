source 'https://rubygems.org'

ruby "2.2.10"
gem 'rails', '4.2.3'
# gem 'bootstrap-sass', '~> 3.3.6'
gem 'simple_form', '~> 3.1.0'			# run 'rails generate simple_form:install --bootstrap' after installing gem
gem 'pg', '~> 0.20.0' 						# Use postgresql as the database for ActiveRecord
gem 'sass-rails', '>= 3.2'        # Use SCSS for stylesheets
# gem 'turbolinks' 									# Turbolinks makes following links in your web application faster.
                                    # (creates some weird caching issues so don't include it unless absolutely necessary)
gem 'jbuilder', '~> 1.2' 					# Build JSON APIs with ease. Read more: https://github.com/rails/jbuilder
gem 'devise', '~> 3.4.1' 					# User Authentication
gem "omniauth-google-oauth2"
gem 'omniauth-microsoft_v2_auth'
gem 'oauth2', '~> 1.4.1'
gem 'faraday', '~> 0.15.3'
gem 'omniauth-oauth2', '~> 1.4'
gem 'hashie', '~> 3.4.3'
gem "jquery-rails"
gem 'friendly_code'
gem 'best_in_place', '~> 3.1.0'
gem 'ahoy_email'
gem 'ahoy_matey','~> 1.6.1'       # Analytics for Rails https://github.com/ankane/ahoy
gem 'puma'                        # Web server
gem 'acts_as_commentable'
gem 'pg_search'
gem 'attr_encrypted', '~> 3.0.0'  # Encrypting private data!
# gem 'paranoia', '~> 2.1', '>= 2.1.5'  # Soft Delete for Rails Models
gem 'omniauth-salesforce'
gem 'restforce', '~> 2.5.0'  #saleforce REST gem
gem 'd3-rails', '~> 3.5'          # Use D3 for cool data visualizations
gem 'slack-notifier'
gem 'device_detector'
gem 'geocoder'
gem 'rack-cors', :require => 'rack/cors'
gem 'graphql'
#gem 'fullcontact', '~>0.18'
gem 'mail'
gem 'mini_mime'
gem 'stripe'
gem 'email_validator'
gem 'kaminari'
gem 'google-api-client', '~>0.19'
gem 'ffi', '1.9.22'
gem 'puma_worker_killer'
gem 'aws-healthcheck'

# Gems used only for assets and not required
# in production environments by default.
group :assets do
  gem 'coffee-rails', '~> 4.0.1'
  gem 'uglifier', '>= 1.3.0'
  # gem 'therubyracer'
end

group :doc do
  # bundle exec rake doc:rails generates the API under doc/api.
  gem 'sdoc', require: false
end

group :development do
  # View schema in models
  gem 'annotate', '~> 2.6.8'
  gem 'ffaker'                    # generate fake data
  gem "letter_opener"             # email preview
  gem 'tzinfo-data', platforms: [:mingw, :mswin, :x64_mingw]  # Time zone info required for running app on Windows environment
  gem 'thin'
end

group :production do
  gem 'exception_notification'
end

group :production, :test do
  gem 'rails_12factor'
end
