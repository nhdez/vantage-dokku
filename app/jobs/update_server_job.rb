class UpdateServerJob < ApplicationJob
  queue_as :default

  def perform(server_id, user_id)
    server = Server.find(server_id)
    uuid = server.uuid

    broadcast(uuid, type: "started", message: "Starting system update on #{server.name}...")

    service = SshConnectionService.new(server)
    result = service.update_server_packages do |line|
      broadcast(uuid, type: "output", message: line) if line.present?
    end

    reboot_required = result[:output]&.include?("REBOOT_REQUIRED") || false
    message = if result[:success]
      reboot_required ?
        "Server updated successfully! A reboot is required to complete some updates." :
        "Server updated successfully! All packages are up to date."
    else
      result[:error]
    end

    broadcast(uuid, type: "completed", success: result[:success], message: message, reboot_required: reboot_required)

  rescue StandardError => e
    Rails.logger.error "Background server update failed: #{e.message}"
    broadcast(uuid, type: "completed", success: false, message: "An unexpected error occurred: #{e.message}")
  end

  private

  def broadcast(uuid, payload)
    ActionCable.server.broadcast("update_server_#{uuid}", payload)
  end
end
