# Configure SMTP settings on application startup
Rails.application.config.after_initialize do
  # Only configure SMTP settings after the database is ready and models are loaded
  begin
    # Determine if SMTP should be enabled
    # If USE_REAL_EMAIL is set, use that; otherwise check database setting
    if ENV['USE_REAL_EMAIL'].present?
      smtp_enabled = ENV['USE_REAL_EMAIL']&.downcase == 'true'
    else
      smtp_enabled = defined?(AppSetting) && AppSetting.get('smtp_enabled', false)
    end
    
    if smtp_enabled
      # Use SMTP configuration - prioritize environment variables over database
      ActionMailer::Base.delivery_method = :smtp
      ActionMailer::Base.smtp_settings = {
        address: ENV['SMTP_ADDRESS'] || (defined?(AppSetting) ? AppSetting.get('smtp_address') : nil),
        port: (ENV['SMTP_PORT'] || (defined?(AppSetting) ? AppSetting.get('smtp_port', 587) : 587)).to_i,
        domain: ENV['SMTP_DOMAIN'] || (defined?(AppSetting) ? AppSetting.get('smtp_domain') : nil),
        user_name: ENV['SMTP_USERNAME'] || (defined?(AppSetting) ? AppSetting.get('smtp_username') : nil),
        password: ENV['SMTP_PASSWORD'] || (defined?(AppSetting) ? AppSetting.get('smtp_password') : nil),
        authentication: (ENV['SMTP_AUTHENTICATION'] || (defined?(AppSetting) ? AppSetting.get('smtp_authentication', 'plain') : 'plain')).to_sym,
        enable_starttls_auto: (ENV['SMTP_ENABLE_STARTTLS_AUTO']&.downcase == 'true') || true
      }
      
      Rails.logger.info "SMTP configured with #{ENV['SMTP_ADDRESS'] ? 'environment variables' : 'database settings'} - Address: #{ENV['SMTP_ADDRESS'] || 'from database'}"
    else
      # Use letter_opener for development
      if Rails.env.development?
        ActionMailer::Base.delivery_method = :letter_opener
        Rails.logger.info "Using letter_opener for email delivery in development"
      end
    end
    
    # Set default from address - prioritize environment variable
    from_address = ENV['MAIL_FROM'] || (defined?(AppSetting) ? AppSetting.get('mail_from', 'no-reply@example.com') : 'no-reply@example.com')
    ActionMailer::Base.default_options = { from: from_address }
    
    Rails.logger.info "Mail from address set to: #{from_address}"
    
  rescue StandardError => e
    Rails.logger.warn "Could not configure SMTP settings: #{e.message}"
    # Fallback to development settings
    ActionMailer::Base.delivery_method = :letter_opener if Rails.env.development?
  end
end