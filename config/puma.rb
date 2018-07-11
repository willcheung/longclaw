workers Integer(ENV['WEB_CONCURRENCY'] || 2)
max_thread = Integer(ENV['MAX_THREADS'] || 4)
min_thread = Integer(ENV['MIN_THREADS'] || 8)
threads min_thread, max_thread

preload_app!

rackup      DefaultRackup
port        ENV['PORT']     || 3000
environment ENV['RACK_ENV'] || 'development'

on_worker_boot do
  # Worker specific setup for Rails 4.1+
  # See: https://devcenter.heroku.com/articles/deploying-rails-applications-with-the-puma-web-server#on-worker-boot
  ActiveRecord::Base.establish_connection
end

# reference: https://devcenter.heroku.com/articles/deploying-rails-applications-with-the-puma-web-server