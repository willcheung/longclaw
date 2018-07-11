workers Integer(ENV['WEB_CONCURRENCY'] || 2)
max_thread = Integer(ENV['MAX_THREADS'] || 6)
min_thread = Integer(ENV['MIN_THREADS'] || 6)
threads min_thread, max_thread

preload_app!

rackup      DefaultRackup
port        ENV['PORT']     || 3000
environment ENV['RACK_ENV'] || 'development'

before_fork do
  require 'puma_worker_killer'

  PumaWorkerKiller.enable_rolling_restart(12 * 3600) # 12 hours in seconds
end

on_worker_boot do
  # Worker specific setup for Rails 4.1+
  # See: https://devcenter.heroku.com/articles/deploying-rails-applications-with-the-puma-web-server#on-worker-boot
  ActiveRecord::Base.establish_connection
end

# reference: https://devcenter.heroku.com/articles/deploying-rails-applications-with-the-puma-web-server