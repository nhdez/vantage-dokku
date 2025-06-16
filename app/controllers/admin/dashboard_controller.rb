class Admin::DashboardController < ApplicationController
  include ActivityTrackable
  
  before_action :ensure_admin
  before_action :log_admin_access_activity
  
  def index
    @total_users = User.count
    @admin_users = User.joins(:roles).where(roles: { name: 'admin' }).count
    @recent_users = User.order(created_at: :desc).limit(5)
    @system_stats = {
      total_roles: Role.count,
      recent_logins: @recent_users.count,
      storage_used: "1.2 GB" # Placeholder
    }
  end

  def general_settings
    # Exclude SMTP settings since they have their own dedicated page
    smtp_keys = %w[smtp_enabled smtp_address smtp_port smtp_domain smtp_username smtp_password smtp_authentication mail_from]
    @settings = AppSetting.where.not(key: smtp_keys).order(:key)
  end

  def update_general_settings
    updated_keys = []
    settings_params.each do |key, value|
      setting = AppSetting.find_by(key: key)
      if setting && setting.value != value.to_s
        setting.update!(value: value.to_s)
        updated_keys << key
      end
    end
    
    log_settings_update(current_user, updated_keys) if updated_keys.any?
    
    toast_settings_updated
    redirect_to admin_general_settings_path
  rescue => e
    toast_error("Failed to update settings: #{e.message}", title: "Update Failed")
    redirect_to admin_general_settings_path
  end

  def smtp_settings
    # Define required SMTP environment variables
    required_env_vars = %w[USE_REAL_EMAIL SMTP_ADDRESS SMTP_PORT SMTP_DOMAIN SMTP_USERNAME SMTP_PASSWORD SMTP_AUTHENTICATION MAIL_FROM]
    
    # Check which variables are present and missing
    @present_env_vars = {}
    @missing_env_vars = []
    
    required_env_vars.each do |var|
      if ENV[var].present?
        @present_env_vars[var] = ENV[var]
      else
        @missing_env_vars << var
      end
    end
    
    # Add optional variables that are present
    if ENV['SMTP_ENABLE_STARTTLS_AUTO'].present?
      @present_env_vars['SMTP_ENABLE_STARTTLS_AUTO'] = ENV['SMTP_ENABLE_STARTTLS_AUTO']
    end
    
    @env_fully_configured = @missing_env_vars.empty?
    @using_env_variables = @present_env_vars.any?
    
    # Only load database settings if environment is not fully configured
    unless @env_fully_configured
      @smtp_settings = AppSetting.where(key: %w[smtp_enabled smtp_address smtp_port smtp_domain smtp_username smtp_password smtp_authentication mail_from]).order(:key)
    end
  end

  def update_smtp_settings
    # Check if environment variables are fully configured
    required_env_vars = %w[USE_REAL_EMAIL SMTP_ADDRESS SMTP_PORT SMTP_DOMAIN SMTP_USERNAME SMTP_PASSWORD SMTP_AUTHENTICATION MAIL_FROM]
    env_fully_configured = required_env_vars.all? { |var| ENV[var].present? }
    
    if env_fully_configured
      # Environment variables are fully configured - no database updates needed
      toast_info("SMTP is configured via environment variables. No changes made to database settings.", title: "Environment Configuration Active")
      redirect_to admin_smtp_settings_path
      return
    end
    
    # Environment variables not fully configured, update database settings
    updated_keys = []
    smtp_params.each do |key, value|
      setting = AppSetting.find_by(key: key)
      if setting && setting.value != value.to_s
        setting.update!(value: value.to_s)
        updated_keys << key
      end
    end
    
    if updated_keys.any?
      log_smtp_settings_update(current_user)
      # Update mailer configuration dynamically
      update_mailer_configuration
      toast_smtp_updated
    else
      toast_info("No changes were made to SMTP settings.", title: "No Changes")
    end
    
    redirect_to admin_smtp_settings_path
  rescue => e
    toast_error("Failed to update SMTP settings: #{e.message}", title: "SMTP Update Failed")
    redirect_to admin_smtp_settings_path
  end

  def test_email
    # Ensure mailer configuration is up to date before sending test email
    update_mailer_configuration
    TestMailer.test_email(current_user.email).deliver_now
    toast_test_email_sent
  rescue => e
    toast_error("Failed to send test email: #{e.message}", title: "Email Failed")
  ensure
    redirect_to admin_smtp_settings_path
  end

  def oauth_settings
    log_admin_access_activity
    # Ensure default OAuth settings exist
    OauthSetting.setup_defaults!
    
    @oauth_settings = {
      'google_oauth_enabled' => OauthSetting.find_by(key: 'google_oauth_enabled'),
      'google_client_id' => OauthSetting.find_by(key: 'google_client_id'),
      'google_client_secret' => OauthSetting.find_by(key: 'google_client_secret')
    }
  end

  def update_oauth_settings
    begin
      oauth_params.each do |key, value|
        setting = OauthSetting.find_by(key: key)
        if setting
          if key == 'google_oauth_enabled'
            setting.update!(enabled: value == 'true', value: value)
          else
            setting.update!(value: value)
          end
        end
      end
      
      # Log the update
      log_activity(
        action: 'admin_oauth_settings_updated',
        details: 'Updated OAuth settings configuration'
      )
      
      toast_success("OAuth settings updated successfully!", title: "Settings Updated")
      redirect_to admin_oauth_settings_path
    rescue => e
      toast_error("Error updating OAuth settings: #{e.message}", title: "Update Failed")
      redirect_to admin_oauth_settings_path
    end
  end

  private

  def ensure_admin
    redirect_to root_path, alert: "Access denied" unless current_user&.admin?
  end

  def settings_params
    params.require(:settings).permit(:app_name, :allow_registration, :require_email_confirmation, :maintenance_mode, :max_file_upload_size, :default_user_role, :dokku_install_version)
  end

  def smtp_params
    params.permit(:smtp_enabled, :smtp_address, :smtp_port, :smtp_domain, :smtp_username, :smtp_password, :smtp_authentication, :mail_from)
  end

  def oauth_params
    params.require(:oauth).permit(:google_oauth_enabled, :google_client_id, :google_client_secret)
  end

  def update_mailer_configuration
    # Check if environment variables are fully configured
    required_env_vars = %w[USE_REAL_EMAIL SMTP_ADDRESS SMTP_PORT SMTP_DOMAIN SMTP_USERNAME SMTP_PASSWORD SMTP_AUTHENTICATION MAIL_FROM]
    env_fully_configured = required_env_vars.all? { |var| ENV[var].present? }
    
    if env_fully_configured
      # Use environment variables exclusively
      smtp_enabled = ENV['USE_REAL_EMAIL']&.downcase == 'true'
      
      if smtp_enabled
        ActionMailer::Base.delivery_method = :smtp
        ActionMailer::Base.smtp_settings = {
          address: ENV['SMTP_ADDRESS'],
          port: ENV['SMTP_PORT'].to_i,
          domain: ENV['SMTP_DOMAIN'],
          user_name: ENV['SMTP_USERNAME'],
          password: ENV['SMTP_PASSWORD'],
          authentication: ENV['SMTP_AUTHENTICATION'].to_sym,
          enable_starttls_auto: (ENV['SMTP_ENABLE_STARTTLS_AUTO']&.downcase == 'true') || true
        }
        ActionMailer::Base.default_options = { from: ENV['MAIL_FROM'] }
      else
        ActionMailer::Base.delivery_method = :letter_opener if Rails.env.development?
      end
    else
      # Use database settings
      smtp_enabled = AppSetting.get('smtp_enabled', false)
      
      if smtp_enabled
        ActionMailer::Base.delivery_method = :smtp
        ActionMailer::Base.smtp_settings = {
          address: AppSetting.get('smtp_address'),
          port: AppSetting.get('smtp_port', 587).to_i,
          domain: AppSetting.get('smtp_domain'),
          user_name: AppSetting.get('smtp_username'),
          password: AppSetting.get('smtp_password'),
          authentication: AppSetting.get('smtp_authentication', 'plain').to_sym,
          enable_starttls_auto: true
        }
        ActionMailer::Base.default_options = { from: AppSetting.get('mail_from', 'no-reply@example.com') }
      else
        ActionMailer::Base.delivery_method = :letter_opener if Rails.env.development?
      end
    end
  end

  def log_admin_access_activity
    area = case action_name
    when 'index'
      'dashboard'
    when 'general_settings'
      'general settings'
    when 'smtp_settings'
      'SMTP settings'
    when 'oauth_settings'
      'OAuth settings'
    else
      action_name.humanize
    end
    
    log_admin_access(current_user, area)
  end
end
