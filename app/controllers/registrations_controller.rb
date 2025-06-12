class RegistrationsController < Devise::RegistrationsController
  include ActivityTrackable

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
end