class SessionsController < Devise::SessionsController
  include ActivityTrackable

  protected

  def after_sign_in_path_for(resource)
    log_login(resource)
    toast_login_success(resource.full_name)
    super
  end

  def after_sign_out_path_for(resource_or_scope)
    log_logout(current_user) if current_user
    toast_logout_success
    super
  end
end