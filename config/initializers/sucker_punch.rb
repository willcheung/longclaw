require 'sucker_punch/async_syntax'

ActiveJob::QueueAdapters::SuckerPunchAdapter::JobWrapper.workers 10