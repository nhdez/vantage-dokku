class Users::OmniauthCallbacksController < Devise::OmniauthCallbacksController
  include ActivityTrackable
  include Toastable
  
  def google_oauth2
    unless OauthSetting.google_enabled?
      toast_error("Google sign-in is currently disabled", "Authentication Error")
      redirect_to new_user_session_path and return
    end
    
    @user = User.from_omniauth(request.env["omniauth.auth"])
    
    if @user.persisted?
      # Log the authentication
      log_activity(
        user: @user,
        action: @user.provider.present? ? 'oauth_signin' : 'oauth_signup',
        details: "Signed #{@user.provider.present? ? 'in' : 'up'} with Google OAuth"
      )
      
      sign_in_and_redirect @user, event: :authentication
      
      if @user.provider.present?
        toast_success("Successfully signed in with Google!", "Welcome back")
      else
        toast_success("Welcome! Your account has been created with Google.", "Account Created")
      end
    else
      session["devise.google_data"] = request.env["omniauth.auth"].except("extra")
      toast_error("There was an error creating your account. Please try again.", "Authentication Error")
      redirect_to new_user_registration_url
    end
  end

  def failure
    toast_error("Authentication failed: #{failure_message}", "Authentication Error")
    redirect_to new_user_session_path
  end

  private

  def failure_message
    case params[:message]
    when 'csrf_detected'
      'Security error detected. Please try again.'
    when 'access_denied'
      'Access was denied. Please try again.'
    when 'invalid_credentials'
      'Invalid credentials provided.'
    else
      'An unexpected error occurred.'
    end
  end
end
