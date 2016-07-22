source 'https://rubygems.org'

ruby "2.2.3"
gem 'rails', '4.2.3'
gem 'bootstrap-sass', '~> 3.3.6'
gem 'simple_form', '~> 3.1.0'			# run 'rails generate simple_form:install --bootstrap' after installing gem
gem 'pg' 													# Use postgresql as the database for ActiveRecord
gem 'sass-rails', '~>5.0.4'       # Use SCSS for stylesheets
# gem 'turbolinks' 									# Turbolinks makes following links in your web application faster. 
                                    # (creates some weird caching issues so don't include it unless absolutely necessary)
gem 'jbuilder', '~> 1.2' 					# Build JSON APIs with ease. Read more: https://github.com/rails/jbuilder
gem 'devise', '~> 3.4.1' 					# User Authentication
gem "omniauth-google-oauth2", :git => 'https://github.com/zquestz/omniauth-google-oauth2', :branch => 'master'
gem "jquery-rails"
gem 'best_in_place', '~> 3.1.0'
gem 'ahoy_email'
gem 'ahoy_matey'                  # Analytics for Rails https://github.com/ankane/ahoy
gem 'puma'                        # Web server
gem 'whois'
gem 'acts_as_commentable'
gem 'pg_search'
# gem 'attr_encrypted', '~> 3.0.0'  # Encrypting private data!
gem 'paranoia', '~> 2.1', '>= 2.1.5'  # Soft Delete for Rails Models
gem 'omniauth-salesforce'  
gem 'restforce'  #saleforce REST gem

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
  gem "rails-erd"                 # run 'brew install graphviz' first, then 'bundle exec erd' to generate erd
  gem 'ffaker'                    # generate fake data
  gem "letter_opener"             # email preview
  gem 'tzinfo-data', platforms: [:mingw, :mswin, :x64_mingw]  # Time zone info required for running app on Windows environment
end

group :production do
  gem 'exception_notification'
end

group :production, :test do
  gem 'rails_12factor'
end
