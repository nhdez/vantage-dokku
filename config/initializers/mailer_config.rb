# Configure ActionMailer based on AppSetting values
Rails.application.configure do
  # Only configure if database is ready and AppSetting exists
  begin
    if defined?(AppSetting) && ActiveRecord::Base.connection.table_exists?('app_settings')
      if AppSetting.get('smtp_enabled', false)
        # Use SMTP configuration
        config.action_mailer.delivery_method = :smtp
        config.action_mailer.smtp_settings = {
          address: AppSetting.get('smtp_address', 'localhost'),
          port: AppSetting.get('smtp_port', 587),
          domain: AppSetting.get('smtp_domain', 'localhost'),
          user_name: AppSetting.get('smtp_username'),
          password: AppSetting.get('smtp_password'),
          authentication: AppSetting.get('smtp_authentication', 'plain').to_sym,
          enable_starttls_auto: true
        }
      else
        # Use letter_opener for development when SMTP is disabled
        if Rails.env.development?
          config.action_mailer.delivery_method = :letter_opener
        end
      end
      
      # Set default from address
      config.action_mailer.default_options = { 
        from: AppSetting.get('mail_from', 'no-reply@example.com') 
      }
    end
  rescue => e
    # Fail silently during migrations or when database is not ready
    Rails.logger.debug "Mailer configuration skipped: #{e.message}" if Rails.logger
  end
end