namespace :app do
  namespace :demo do
    desc "Load demo data"
    task load: :environment do
      # Load fixtures
      require 'active_record/fixtures'
      Dir.glob(Rails.root.join('db', 'demo', '*.{yml,csv}')).each do |fixture_file|
        ActiveRecord::Fixtures.create_fixtures(Rails.root.join('db/demo'), File.basename(fixture_file, '.*'))
      end

      # Simulate random user activities.
      $stdout.sync = true
      puts "Generating user activities..."
      %w(Contact).map do |model|
        model.constantize.all
      end
    end
  end
end
