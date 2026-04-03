# Handles boot, reboot, and remove operations for Kamal accessories.
# The `operation` param is one of: "boot", "reboot", "remove"
class KamalAccessoryJob < ApplicationJob
  queue_as :default

  def perform(deployment, accessory_name, operation)
    channel = "deployment_logs_#{deployment.uuid}"
    accessory = deployment.kamal_configuration.kamal_accessories.find_by(name: accessory_name)

    ActionCable.server.broadcast(channel, {
      type: "log_message",
      message: "#{operation.capitalize}ing accessory '#{accessory_name}'..."
    })

    accessory&.update!(status: "booting") if operation == "boot"

    service = KamalCommandService.new(deployment.kamal_configuration, broadcast_channel: channel)
    result = service.public_send(:"accessory_#{operation}", accessory_name)

    if result[:success]
      accessory&.update!(status: operation == "remove" ? "pending" : "running")
      ActionCable.server.broadcast(channel, { type: "completed", success: true, message: "Accessory #{accessory_name} #{operation} completed." })
    else
      accessory&.update!(status: "failed")
      ActionCable.server.broadcast(channel, { type: "completed", success: false, message: result[:error] || "#{operation.capitalize} failed" })
    end
  rescue StandardError => e
    Rails.logger.error "[KamalAccessoryJob] Exception (#{operation} #{accessory_name}): #{e.message}"
    ActionCable.server.broadcast("deployment_logs_#{deployment.uuid}", { type: "completed", success: false, message: e.message })
  end
end
