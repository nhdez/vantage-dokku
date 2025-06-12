module ActivityTrackable
  extend ActiveSupport::Concern

  private

  def log_activity(action, details: nil, user: current_user)
    return unless user

    ActivityLog.log_activity(
      user: user,
      action: action,
      details: details,
      request: request,
      controller_name: controller_name,
      action_name: action_name,
      params_data: filter_sensitive_params(params)
    )
  rescue => e
    Rails.logger.error "Failed to log activity: #{e.message}"
  end

  def log_login(user)
    log_activity(ActivityLog::ACTIONS[:login], 
                details: "Signed in from #{request.remote_ip}", 
                user: user)
  end

  def log_logout(user)
    log_activity(ActivityLog::ACTIONS[:logout], 
                details: "Signed out", 
                user: user)
  end

  def log_profile_update(user, changes = {})
    changed_fields = changes.keys.join(', ') if changes.any?
    log_activity(ActivityLog::ACTIONS[:profile_update], 
                details: "Updated: #{changed_fields}", 
                user: user)
  end

  def log_password_change(user)
    log_activity(ActivityLog::ACTIONS[:password_change], 
                details: "Password changed", 
                user: user)
  end

  def log_role_assignment(user, role_name, target_user)
    log_activity(ActivityLog::ACTIONS[:role_assigned], 
                details: "Assigned '#{role_name}' role to #{target_user.full_name}", 
                user: user)
  end

  def log_role_removal(user, role_name, target_user)
    log_activity(ActivityLog::ACTIONS[:role_removed], 
                details: "Removed '#{role_name}' role from #{target_user.full_name}", 
                user: user)
  end

  def log_settings_update(user, setting_keys = [])
    details = setting_keys.any? ? "Updated: #{setting_keys.join(', ')}" : "Updated application settings"
    log_activity(ActivityLog::ACTIONS[:settings_update], 
                details: details, 
                user: user)
  end

  def log_smtp_settings_update(user)
    log_activity(ActivityLog::ACTIONS[:smtp_settings_update], 
                details: "Updated SMTP configuration", 
                user: user)
  end

  def log_admin_access(user, area = nil)
    details = area ? "Accessed admin #{area}" : "Accessed admin area"
    log_activity(ActivityLog::ACTIONS[:admin_access], 
                details: details, 
                user: user)
  end

  private

  def filter_sensitive_params(params_hash)
    # Remove sensitive data from params before logging
    filtered = params_hash.except(:password, :password_confirmation, :current_password, :smtp_password)
    filtered.respond_to?(:to_unsafe_h) ? filtered.to_unsafe_h : filtered.to_h
  end
end