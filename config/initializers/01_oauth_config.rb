# Load OAuth settings from database before Devise initializes
# This allows admin users to configure OAuth through the web interface

Rails.application.config.before_configuration do
  begin
    puts "OAuth Config: Starting OAuth configuration (#{Rails.env})"
    
    # Skip if environment variables are already set
    if ENV['GOOGLE_CLIENT_ID'].present? && ENV['GOOGLE_CLIENT_SECRET'].present?
      puts "OAuth Config: Environment variables already set, skipping database load"
      next
    end
    
    # Only try in environments where database should be available
    unless Rails.env.development? || Rails.env.production?
      puts "OAuth Config: Skipping - not in development or production"
      next
    end
    
    puts "OAuth Config: Loading models..."
    # Load OAuth settings from database
    require_relative '../../app/models/application_record'
    require_relative '../../app/models/oauth_setting'
    
    puts "OAuth Config: OauthSetting defined: #{defined?(OauthSetting).present?}"
    
    if defined?(OauthSetting)
      table_exists = OauthSetting.table_exists?
      puts "OAuth Config: Table exists: #{table_exists}"
      
      if table_exists
        google_enabled = OauthSetting.google_enabled?
        puts "OAuth Config: Google enabled: #{google_enabled}"
        
        if google_enabled
          client_id = OauthSetting.google_client_id
          client_secret = OauthSetting.google_client_secret
          
          puts "OAuth Config: Client ID present: #{client_id.present?}"
          puts "OAuth Config: Client secret present: #{client_secret.present?}"
          
          if client_id.present? && client_secret.present?
            ENV['GOOGLE_CLIENT_ID'] = client_id
            ENV['GOOGLE_CLIENT_SECRET'] = client_secret
            puts "OAuth Config: Successfully loaded credentials from database"
          else
            puts "OAuth Config: Missing credentials in database"
          end
        else
          puts "OAuth Config: Google OAuth disabled in database"
        end
      end
    end
    
  rescue => e
    puts "OAuth Config: Error loading from database: #{e.message}"
    puts "OAuth Config: #{e.backtrace.first(3).join(', ')}"
  end
end