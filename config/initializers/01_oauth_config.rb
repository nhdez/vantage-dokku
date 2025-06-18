# Load OAuth settings from database before Devise initializes
# This allows admin users to configure OAuth through the web interface

Rails.application.config.before_configuration do
  begin
    # Skip if environment variables are already set
    next if ENV['GOOGLE_CLIENT_ID'].present? && ENV['GOOGLE_CLIENT_SECRET'].present?
    
    # Only try in environments where database should be available
    next unless Rails.env.development? || Rails.env.production?
    
    # Load OAuth settings from database
    require_relative '../../app/models/application_record'
    require_relative '../../app/models/oauth_setting'
    
    if defined?(OauthSetting) && OauthSetting.table_exists? && OauthSetting.google_enabled?
      client_id = OauthSetting.google_client_id
      client_secret = OauthSetting.google_client_secret
      
      if client_id.present? && client_secret.present?
        ENV['GOOGLE_CLIENT_ID'] = client_id
        ENV['GOOGLE_CLIENT_SECRET'] = client_secret
      end
    end
    
  rescue => e
    # Silently fail if database isn't ready - OAuth just won't be configured
  end
end