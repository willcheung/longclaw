class LoadEventsSinceYesterdayJob < ActiveJob::Base
  queue_as :default

  def perform
    ActiveRecord::Base.connection_pool.with_connection do

      Organization.is_active.each do |org|
        org.accounts.each do |acc|
          acc.projects.is_active.where("stage IS NULL OR stage LIKE '%Closed%'").each do |proj|
            puts "Org: " + org.name + ", Account: " + acc.name + ", Project: " + proj.name
            ContextsmithService.load_calendar_from_backend(proj, 100, 1.day.ago.to_i)
            sleep(1)
          end
        end
      end

    end
  end
end
