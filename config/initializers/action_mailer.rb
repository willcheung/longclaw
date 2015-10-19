Rails.application.configure do
	# Load google api key config file
  api_keys_config_file = File.join(Rails.root,'config','api_keys.yml')
  raise "#{api_keys_config_file} is missing!" unless File.exists? api_keys_config_file
  api_keys_config = YAML.load_file(api_keys_config_file)[Rails.env].symbolize_keys

  config.action_mailer.smtp_settings = {
    :address   => "smtp.mandrillapp.com",
    :port      => 587,
    :enable_starttls_auto => true,
    :user_name => api_keys_config[:mandrill_user_name],
    :password  => api_keys_config[:mandrill_api_key],
    :authentication => 'login',
    :domain => 'contextsmith.com'
  }
end