class OauthDebugController < ApplicationController
  skip_before_action :authenticate_user!
  
  def debug
    # Only allow this in development or for admins
    unless Rails.env.development? || (user_signed_in? && current_user.admin?)
      redirect_to root_path and return
    end
    
    @debug_info = {
      environment: Rails.env,
      oauth_enabled: OauthSetting.google_enabled?,
      client_id_present: OauthSetting.google_client_id.present?,
      client_secret_present: OauthSetting.google_client_secret.present?,
      client_id_value: OauthSetting.google_client_id&.first(10),
      devise_providers: Devise.omniauth_providers,
      env_client_id: ENV['GOOGLE_CLIENT_ID']&.first(10),
      env_client_secret: ENV['GOOGLE_CLIENT_SECRET'].present?
    }
    
    render json: @debug_info
  end
end