# Fix OAuth Setup - Ensure proper Google OAuth configuration
# This runs before routes are finalized to ensure OAuth works correctly

Rails.application.config.before_initialize do
  # Make sure we have the omniauth gem available
  begin
    require 'omniauth'
    require 'omniauth-google-oauth2' 
    require 'omniauth-rails_csrf_protection'
  rescue LoadError => e
    Rails.logger.error "OAuth gems not available: #{e.message}"
  end
end

Rails.application.config.after_initialize do
  # Ensure routes are loaded with proper OAuth configuration
  Rails.application.reload_routes_unless_loaded if defined?(Rails::Console)
end