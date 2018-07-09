workers Integer(ENV['WEB_CONCURRENCY'] || 3)
threads_count = Integer(ENV['MAX_THREADS'] || 4)
threads threads_count, threads_count

# https://stackoverflow.com/questions/30355569/rails-application-deployed-on-elastic-beanstalk-with-puma-fails-502-errors-on
bind "unix:///var/run/puma/my_app.sock"
pidfile "/var/run/puma/my_app.sock"

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