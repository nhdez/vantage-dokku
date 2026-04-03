class Admin::DashboardController < ApplicationController
  include ActivityTrackable

  before_action :ensure_admin
  before_action :log_admin_access_activity

  def index
    @total_users = User.count
    @admin_users = User.joins(:roles).where(roles: { name: "admin" }).count
    @recent_users = User.order(created_at: :desc).limit(5)
    @system_stats = {
      total_roles: Role.count,
      recent_logins: @recent_users.count,
      storage_used: "1.2 GB" # Placeholder
    }
  end

  def general_settings
    # Exclude SMTP and SSH settings since they have their own dedicated pages or are deprecated
    smtp_keys = %w[smtp_enabled smtp_address smtp_port smtp_domain smtp_username smtp_password smtp_authentication mail_from]
    ssh_keys = %w[dokku_ssh_private_key dokku_ssh_public_key dokku_ssh_key_path]
    excluded_keys = smtp_keys + ssh_keys

    @settings = AppSetting.where.not(key: excluded_keys).order(:key)
  end

  def update_general_settings
    updated_keys = []

    # Handle regular settings
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
    required_env_vars = %w[SMTP_ADDRESS SMTP_PORT SMTP_DOMAIN SMTP_USERNAME SMTP_PASSWORD SMTP_AUTHENTICATION MAIL_FROM]

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

    @env_fully_configured = @missing_env_vars.empty?
    @smtp_enabled_setting = AppSetting.find_by(key: "smtp_enabled")
  end

  def update_smtp_settings
    begin
      enabled_setting = AppSetting.find_by(key: "smtp_enabled")
      enabled_param = params.dig(:smtp_enabled) == "true"

      if enabled_setting
        enabled_setting.update!(value: enabled_param.to_s)
      end

      log_smtp_settings_update(current_user)
      toast_smtp_updated

      # Add a notice about restarting the server
      flash[:info] = "Changes to SMTP settings may require an application restart to take full effect."

    rescue => e
      toast_error("Failed to update SMTP settings: #{e.message}", title: "SMTP Update Failed")
    end

    redirect_to admin_smtp_settings_path
  end

  def test_email
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

    @google_oauth_enabled = OauthSetting.find_by(key: "google_oauth_enabled")
    @google_client_id = ENV["GOOGLE_CLIENT_ID"]
    @google_client_secret = ENV["GOOGLE_CLIENT_SECRET"]
    @google_creds_set = @google_client_id.present? && @google_client_secret.present?
  end

  def update_oauth_settings
    begin
      enabled_setting = OauthSetting.find_by(key: "google_oauth_enabled")
      enabled_param = params.dig(:oauth, :google_oauth_enabled) == "true"

      if enabled_setting
        enabled_setting.update!(enabled: enabled_param, value: enabled_param.to_s)
      end

      # Log the update
      log_activity("admin_oauth_settings_updated",
                  details: "Updated Google OAuth enabled status to #{enabled_param}")

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



  def log_admin_access_activity
    area = case action_name
    when "index"
      "dashboard"
    when "general_settings"
      "general settings"
    when "smtp_settings"
      "SMTP settings"
    when "oauth_settings"
      "OAuth settings"
    else
      action_name.humanize
    end

    log_admin_access(current_user, area)
  end
end
