class Ahoy::Store < Ahoy::Stores::ActiveRecordStore
  # customize here

  def report_exception(e)
    Rollbar.report_exception(e)
  end
end
