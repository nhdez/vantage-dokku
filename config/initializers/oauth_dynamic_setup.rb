# Dynamic OAuth Configuration
# This initializer handles dynamic Google OAuth setup after the database is available

Rails.application.config.after_initialize do
  # Skip during asset precompilation, rake tasks, or when database is not available
  next if defined?(Rails::Console) || Rails.env.test? || $PROGRAM_NAME.include?('rake')
  next if ENV['SKIP_OAUTH_SETUP'] == 'true' || ENV['PRECOMPILING_ASSETS'] == '1'
  
  # Check if we can connect to the database before setting up OAuth
  begin
    ActiveRecord::Base.connection.execute('SELECT 1')
  rescue => e
    Rails.logger.info "Skipping OAuth setup - database not available: #{e.message}"
    next
  end
  
  # Only proceed if OauthSetting model is available
  if defined?(OauthSetting) && OauthSetting.table_exists?
    begin
      # Get OAuth settings from database
      google_enabled = OauthSetting.google_enabled?
      google_client_id = OauthSetting.google_client_id
      google_client_secret = OauthSetting.google_client_secret
      
      # Also check environment variables which take precedence
      google_client_id = ENV['GOOGLE_CLIENT_ID'].presence || google_client_id
      google_client_secret = ENV['GOOGLE_CLIENT_SECRET'].presence || google_client_secret
      
      if google_enabled && google_client_id.present? && google_client_secret.present?
        # Clear any existing Google OAuth provider
        Devise.omniauth_providers.delete(:google_oauth2) if Devise.omniauth_providers.include?(:google_oauth2)
        
        # Add Google OAuth provider with current settings
        Devise.setup do |config|
          config.omniauth :google_oauth2,
            google_client_id,
            google_client_secret,
            {
              scope: 'userinfo.email,userinfo.profile',
              prompt: 'consent',
              image_aspect_ratio: 'square',
              image_size: 50,
              skip_jwt: true
            }
        end
        
        Rails.logger.info "Google OAuth configured with client ID: #{google_client_id[0..10]}..."
      else
        Rails.logger.info "Google OAuth not configured - missing credentials or disabled"
      end
      
    rescue => e
      Rails.logger.error "Failed to setup dynamic OAuth configuration: #{e.message}"
    end
  end
end