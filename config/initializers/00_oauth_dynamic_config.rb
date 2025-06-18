# Dynamic OAuth Configuration
# This creates a method that the application can call to reload OAuth settings

class OAuthConfigurator
  def self.configure_from_database!
    return unless defined?(OauthSetting) && OauthSetting.table_exists?
    
    # Skip if environment variables are configured (they take precedence)
    if ENV['GOOGLE_CLIENT_ID'].present? && ENV['GOOGLE_CLIENT_SECRET'].present?
      Rails.logger.info "OAuth Config: Using environment variables"
      return
    end
    
    # Get OAuth settings from database
    if OauthSetting.google_enabled?
      client_id = OauthSetting.google_client_id
      client_secret = OauthSetting.google_client_secret
      
      if client_id.present? && client_secret.present?
        Rails.logger.info "OAuth Config: Loading credentials from database"
        
        # Set temporary environment variables for this process
        ENV['GOOGLE_CLIENT_ID'] = client_id
        ENV['GOOGLE_CLIENT_SECRET'] = client_secret
        
        # Restart the Rails application to pick up the new OAuth config
        if Rails.env.production?
          Rails.logger.info "OAuth Config: Production restart recommended for OAuth changes"
        else
          Rails.logger.info "OAuth Config: OAuth credentials loaded from database"
        end
        
        return true
      else
        Rails.logger.info "OAuth Config: Google OAuth enabled but missing credentials"
      end
    else
      Rails.logger.info "OAuth Config: Google OAuth disabled in database"
    end
    
    false
  end
end

# Load OAuth settings from database BEFORE Devise initializer runs
# This runs during Rails.application.initialize! process
Rails.application.config.before_configuration do
  begin
    # Only try to connect to database if we're in an environment where it should be available
    next unless Rails.env.development? || Rails.env.production?
    
    # Load dotenv first if in development
    if Rails.env.development? && defined?(Dotenv)
      Dotenv::Railtie.load
    end
    
    # Skip if environment variables are already set
    next if ENV['GOOGLE_CLIENT_ID'].present? && ENV['GOOGLE_CLIENT_SECRET'].present?
    
    # Try to establish database connection and load OAuth settings
    require 'active_record'
    require_relative '../../app/models/application_record'
    require_relative '../../app/models/oauth_setting'
    
    # Check if database exists and table exists
    if defined?(OauthSetting) && OauthSetting.table_exists?
      if OauthSetting.google_enabled?
        client_id = OauthSetting.google_client_id
        client_secret = OauthSetting.google_client_secret
        
        if client_id.present? && client_secret.present?
          ENV['GOOGLE_CLIENT_ID'] = client_id
          ENV['GOOGLE_CLIENT_SECRET'] = client_secret
          puts "OAuth Config: Loaded Google OAuth credentials from database"
        end
      end
    end
    
  rescue => e
    puts "OAuth Config: Could not load from database: #{e.message}"
  end
end