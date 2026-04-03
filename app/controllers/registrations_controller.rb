class RegistrationsController < Devise::RegistrationsController
  include ActivityTrackable

  before_action :check_registration_status, only: [ :new, :create ]

  protected

  def update_resource(resource, params)
    # Track what changed before updating
    changes = resource.changes if resource.changed?

    result = super

    if result
      if params[:password].present?
        log_password_change(resource)
        toast_success("Your password has been updated successfully!", title: "Password Updated")
      else
        log_profile_update(resource, changes || {})
        toast_updated("Profile")
      end
    else
      toast_validation_errors(resource)
    end

    result
  end

  private

  def check_registration_status
    unless AppSetting.get("allow_registration", true)
      flash[:alert] = "User registration is currently disabled."
      redirect_to new_user_session_path
    end
  end
end
