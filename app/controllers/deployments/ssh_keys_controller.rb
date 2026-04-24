class Deployments::SshKeysController < Deployments::BaseController
  def attach_ssh_keys
    @available_ssh_keys = current_user.ssh_keys.active.order(:name)
    @attached_ssh_keys = @deployment.ssh_keys
    log_activity("ssh_keys_attachment_viewed", details: "Viewed SSH key attachment for deployment: #{@deployment.display_name}")
  end

  def update_ssh_keys
    ssh_key_ids = params[:ssh_key_ids] || []

    new_ssh_keys = current_user.ssh_keys.where(id: ssh_key_ids)
    current_ssh_keys = @deployment.ssh_keys

    keys_to_attach = new_ssh_keys - current_ssh_keys
    keys_to_detach = current_ssh_keys - new_ssh_keys

    @deployment.ssh_keys = new_ssh_keys

    service = SshConnectionService.new(@deployment.server)
    result = service.sync_dokku_ssh_keys(@deployment.ssh_keys.pluck(:public_key))

    if result[:success]
      attached_count = keys_to_attach.count
      detached_count = keys_to_detach.count

      message_parts = []
      message_parts << "#{attached_count} key#{'s' unless attached_count == 1} attached" if attached_count > 0
      message_parts << "#{detached_count} key#{'s' unless detached_count == 1} detached" if detached_count > 0
      message_parts << "No changes made" if attached_count == 0 && detached_count == 0

      log_activity("ssh_keys_updated", details: "Updated SSH keys for deployment: #{@deployment.display_name} - #{message_parts.join(', ')}")
      toast_success("SSH keys updated successfully! #{message_parts.join(', ').capitalize}.", title: "Keys Updated")
    else
      log_activity("ssh_keys_sync_failed", details: "Failed to sync SSH keys for deployment: #{@deployment.display_name} - #{result[:error]}")
      toast_error("Failed to sync SSH keys to server: #{result[:error]}", title: "Sync Failed")
    end
  rescue StandardError => e
    Rails.logger.error "SSH key update failed: #{e.message}"
    toast_error("An unexpected error occurred: #{e.message}", title: "Update Error")
  ensure
    redirect_to attach_ssh_keys_deployment_path(@deployment)
  end
end
