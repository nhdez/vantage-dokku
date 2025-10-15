# config/initializers/mailer_settings.rb

# This initializer configures Action Mailer based on environment variables
# for production-like environments, or falls back to database settings
# for flexibility in development or other setups.

# Define the required environment variables for a full SMTP configuration
REQUIRED_SMTP_ENV_VARS = %w[
  SMTP_ADDRESS SMTP_PORT SMTP_DOMAIN SMTP_USERNAME 
  SMTP_PASSWORD SMTP_AUTHENTICATION MAIL_FROM
].freeze

# Check if all required environment variables are present
env_fully_configured = REQUIRED_SMTP_ENV_VARS.all? { |var| ENV[var].present? }

# Use a flag from ENV to determine if real emails should be sent
use_real_email = ENV['USE_REAL_EMAIL']&.downcase == 'true'

if env_fully_configured && use_real_email
  # If fully configured via ENV and enabled, use SMTP with ENV variables
  ActionMailer::Base.delivery_method = :smtp
  ActionMailer::Base.smtp_settings = {
    address:        ENV['SMTP_ADDRESS'],
    port:           ENV['SMTP_PORT'].to_i,
    domain:         ENV['SMTP_DOMAIN'],
    user_name:      ENV['SMTP_USERNAME'],
    password:       ENV['SMTP_PASSWORD'],
    authentication: ENV['SMTP_AUTHENTICATION'].to_sym,
    enable_starttls_auto: (ENV['SMTP_ENABLE_STARTTLS_AUTO']&.downcase != 'false') # Defaults to true
  }
  ActionMailer::Base.default_options = { from: ENV['MAIL_FROM'] }
  
  Rails.logger.info "[Mailer] Configured to use SMTP via environment variables."
  
elsif Rails.env.development?
  # In development, default to letter_opener if not fully configured for SMTP
  ActionMailer::Base.delivery_method = :letter_opener
  ActionMailer::Base.perform_deliveries = true
  
  Rails.logger.info "[Mailer] Configured to use letter_opener for development."
  
else
  # For other environments (like production without full ENV config),
  # you might want to log a warning or prevent mail delivery.
  # For now, we'll default to test delivery method to avoid errors.
  ActionMailer::Base.delivery_method = :test
  
  Rails.logger.warn "[Mailer] SMTP environment variables are not fully configured. Email delivery is disabled."
end

# Ensure the correct delivery method is used in test environment
if Rails.env.test?
  ActionMailer::Base.delivery_method = :test
end
