class ThemesController < ApplicationController
  before_action :authenticate_user!
  include ActivityTrackable
  include Toastable

  def update
    if current_user.update(theme_params)
      log_activity(
        action: 'theme_changed',
        details: "Changed theme preference to '#{current_user.theme}'"
      )
      
      render json: { 
        status: 'success', 
        theme: current_user.theme,
        message: "Theme updated to #{current_user.theme.titleize} mode" 
      }
    else
      render json: { 
        status: 'error', 
        errors: current_user.errors.full_messages,
        message: 'Failed to update theme preference' 
      }, status: :unprocessable_entity
    end
  end

  private

  def theme_params
    params.require(:user).permit(:theme)
  end
end
