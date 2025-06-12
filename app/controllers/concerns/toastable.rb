module Toastable
  extend ActiveSupport::Concern

  # Enhanced flash methods for beautiful toasts
  def toast_success(message, title: nil)
    flash[:success] = message
    flash[:success_title] = title if title
  end

  def toast_error(message, title: nil)
    flash[:error] = message
    flash[:error_title] = title if title
  end

  def toast_warning(message, title: nil)
    flash[:warning] = message
    flash[:warning_title] = title if title
  end

  def toast_info(message, title: nil)
    flash[:info] = message
    flash[:info_title] = title if title
  end

  # For backwards compatibility
  def toast_notice(message, title: nil)
    flash[:notice] = message
    flash[:notice_title] = title if title
  end

  def toast_alert(message, title: nil)
    flash[:alert] = message
    flash[:alert_title] = title if title
  end

  # Quick action-specific toasts
  def toast_saved(resource_name = "Record")
    toast_success("#{resource_name} has been saved successfully!", title: "Saved!")
  end

  def toast_updated(resource_name = "Record")
    toast_success("#{resource_name} has been updated successfully!", title: "Updated!")
  end

  def toast_deleted(resource_name = "Record")
    toast_success("#{resource_name} has been deleted successfully!", title: "Deleted!")
  end

  def toast_created(resource_name = "Record")
    toast_success("#{resource_name} has been created successfully!", title: "Created!")
  end

  def toast_login_success(user_name = nil)
    message = user_name ? "Welcome back, #{user_name}!" : "You have been signed in successfully!"
    toast_success(message, title: "Welcome!")
  end

  def toast_logout_success
    toast_success("You have been signed out successfully. See you soon!", title: "Goodbye!")
  end

  def toast_permission_denied
    toast_error("You don't have permission to perform this action.", title: "Access Denied")
  end

  def toast_not_found
    toast_error("The requested resource could not be found.", title: "Not Found")
  end

  def toast_validation_errors(model)
    if model.errors.any?
      errors = model.errors.full_messages.join(', ')
      toast_error("Please fix the following errors: #{errors}", title: "Validation Failed")
    end
  end

  # Admin-specific toasts
  def toast_role_assigned(role_name, user_name)
    toast_success("Successfully assigned '#{role_name}' role to #{user_name}!", title: "Role Assigned")
  end

  def toast_role_removed(role_name, user_name)
    toast_success("Successfully removed '#{role_name}' role from #{user_name}!", title: "Role Removed")
  end

  def toast_settings_updated
    toast_success("Application settings have been updated successfully!", title: "Settings Updated")
  end

  def toast_smtp_updated
    toast_success("SMTP configuration has been updated successfully!", title: "SMTP Updated")
  end

  def toast_test_email_sent
    toast_success("Test email has been sent successfully! Check your inbox.", title: "Email Sent")
  end
end