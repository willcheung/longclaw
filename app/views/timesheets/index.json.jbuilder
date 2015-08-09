json.array!(@timesheets) do |timesheet|
  json.extract! timesheet, :id
  json.url timesheet_url(timesheet, format: :json)
end
