class Ahoy::Store < Ahoy::Stores::ActiveRecordStore
  # customize here

  def report_exception(e)
    Rollbar.report_exception(e)
  end
end

 Ahoy.visit_duration = 30.minutes # Same as Google Analytics
 Ahoy.geocode = :async