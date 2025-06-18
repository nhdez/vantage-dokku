class Users::OmniauthCallbacksController < Devise::OmniauthCallbacksController
  include ActivityTrackable
  include Toastable
  
  def google_oauth2
    user = User.from_google(from_google_params)

    if user.present?
      sign_out_all_scopes
      flash[:notice] = t 'devise.omniauth_callbacks.success', kind: 'Google'
      sign_in_and_redirect user, event: :authentication
    else
      flash[:alert] = t 'devise.omniauth_callbacks.failure', kind: 'Google', reason: "#{auth.info.email} is not authorized."
      redirect_to new_user_session_path
    end
  end

  private

  def from_google_params
    @from_google_params ||= {
      uid: auth.uid,
      email: auth.info.email,
      first_name: auth.info.first_name,
      last_name: auth.info.last_name,
      image: auth.info.image
    }
  end

  def auth
    @auth ||= request.env['omniauth.auth']
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
