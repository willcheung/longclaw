source 'https://rubygems.org'

gem 'rails', '4.2.3'
gem 'bootstrap-sass', '~> 3.3.5'
gem 'simple_form', '~> 3.1.0'			# run 'rails generate simple_form:install --bootstrap' after installing gem
gem "cocoon"
gem 'pg' 													# Use postgresql as the database for Active Record
gem 'sass-rails', '~> 4.0.0' 			# Use SCSS for stylesheets
# gem 'turbolinks' 									# Turbolinks makes following links in your web application faster. 
gem 'jbuilder', '~> 1.2' 					# Build JSON APIs with ease. Read more: https://github.com/rails/jbuilder
gem 'devise', '~> 3.4.1' 					# User Authentication
gem "omniauth-google-oauth2"
gem "jquery-rails"
gem 'best_in_place', '~> 3.0.1'
gem 'ahoy_email'
gem 'ahoy_matey'                  # Analytics for Rails https://github.com/ankane/ahoy
gem 'puma'                        # Production web server

# Gems used only for assets and not required
# in production environments by default.
group :assets do
  gem 'coffee-rails', '~> 4.0.1'
  gem 'uglifier', '>= 1.3.0'
  gem 'therubyracer'
end

group :doc do
  # bundle exec rake doc:rails generates the API under doc/api.
  gem 'sdoc', require: false
end

group :development do
  # View schema in models
  gem 'annotate', '~> 2.6.8'
  gem "rails-erd" 								# run 'brew install graphviz' first, then 'bundle exec erd' to generate erd
  gem 'ffaker'										# generate fake data
  gem "letter_opener"							# email preview
end

gem 'rails_12factor', group: :production

# Use ActiveModel has_secure_password
# gem 'bcrypt-ruby', '~> 3.1.2'

# Use unicorn as the app server
# gem 'unicorn'

# Use Capistrano for deployment
# gem 'capistrano', group: :development

# Use debugger
# gem 'debugger', group: [:development, :test]
