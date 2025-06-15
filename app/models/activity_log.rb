class ActivityLog < ApplicationRecord
  belongs_to :user

  validates :action, presence: true
  validates :occurred_at, presence: true

  scope :recent, -> { order(occurred_at: :desc) }
  scope :by_action, ->(action) { where(action: action) }
  scope :by_user, ->(user) { where(user: user) }
  scope :today, -> { where(occurred_at: Date.current.beginning_of_day..Date.current.end_of_day) }
  scope :this_week, -> { where(occurred_at: 1.week.ago..Time.current) }

  # Log an activity for a user
  def self.log_activity(user:, action:, details: nil, request: nil, controller_name: nil, action_name: nil, params_data: nil)
    create!(
      user: user,
      action: action,
      details: details,
      ip_address: request&.remote_ip,
      user_agent: request&.user_agent,
      occurred_at: Time.current,
      controller_name: controller_name,
      action_name: action_name,
      params_data: params_data&.to_json,
    )
  end

  # Common activity types
  ACTIONS = {
    login: 'login',
    logout: 'logout',
    profile_update: 'profile_update',
    password_change: 'password_change',
    role_assigned: 'role_assigned',
    role_removed: 'role_removed',
    settings_update: 'settings_update',
    smtp_settings_update: 'smtp_settings_update',
    user_created: 'user_created',
    user_updated: 'user_updated',
    admin_access: 'admin_access',
    two_factor_enabled: 'two_factor_enabled',
    two_factor_disabled: 'two_factor_disabled'
  }.freeze

  def action_display
    action.humanize.titleize
  end

  def details_summary
    case action
    when 'login'
      'User signed in'
    when 'logout'
      'User signed out'
    when 'profile_update'
      'Updated profile information'
    when 'password_change'
      'Changed password'
    when 'role_assigned'
      details || 'Role assigned'
    when 'role_removed'
      details || 'Role removed'
    when 'settings_update'
      'Updated application settings'
    when 'smtp_settings_update'
      'Updated SMTP configuration'
    else
      details || action_display
    end
  end

  def browser_info
    return 'Unknown' unless user_agent.present?
    
    # Simple browser detection
    case user_agent
    when /Chrome/
      'Chrome'
    when /Firefox/
      'Firefox'
    when /Safari/
      'Safari'
    when /Edge/
      'Edge'
    else
      'Other'
    end
  end
end
