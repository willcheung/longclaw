class LoadEmailsSinceYesterdayJob < ActiveJob::Base
  queue_as :default

  def perform
    ActiveRecord::Base.connection_pool.with_connection do

      Organization.is_active.each do |org|
        org.accounts.each do |acc|
          acc.projects.is_active.each do |proj|
            puts "Org: " + org.name + ", Account: " + acc.name + ", Project/Stream: " + proj.name
            ContextsmithService.load_emails_from_backend(proj)
            sleep(1)
          end
        end
      end

    end
  end
end
