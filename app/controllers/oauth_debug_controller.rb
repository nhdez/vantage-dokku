class OauthDebugController < ApplicationController
  skip_before_action :authenticate_user!
  
  def debug
    # Only allow this in development or for admins
    unless Rails.env.development? || (user_signed_in? && current_user.admin?)
      redirect_to root_path and return
    end
    
    @debug_info = {
      environment: Rails.env,
      rails_env: Rails.env.to_s,
      oauth_setting_defined: defined?(OauthSetting).present?,
      oauth_setting_table_exists: (defined?(OauthSetting) && OauthSetting.table_exists?),
      oauth_enabled: (defined?(OauthSetting) && OauthSetting.table_exists?) ? OauthSetting.google_enabled? : false,
      client_id_present: (defined?(OauthSetting) && OauthSetting.table_exists?) ? OauthSetting.google_client_id.present? : false,
      client_secret_present: (defined?(OauthSetting) && OauthSetting.table_exists?) ? OauthSetting.google_client_secret.present? : false,
      client_id_value: (defined?(OauthSetting) && OauthSetting.table_exists?) ? OauthSetting.google_client_id&.first(10) : nil,
      devise_providers: Devise.omniauth_providers,
      devise_configs: Devise.omniauth_configs.keys,
      env_client_id: ENV['GOOGLE_CLIENT_ID']&.first(10),
      env_client_secret: ENV['GOOGLE_CLIENT_SECRET'].present?,
      initializer_01_exists: File.exist?(Rails.root.join('config/initializers/01_oauth_config.rb')),
      before_configuration_hook: 'Check server logs for OAuth loading messages'
    }
    
    render json: @debug_info
  end
end