# Handles restart, stop, and start operations for Kamal apps.
# The `operation` param is one of: "restart", "stop", "start"
class KamalAppLifecycleJob < ApplicationJob
  queue_as :default

  def perform(deployment, operation)
    channel = "deployment_logs_#{deployment.uuid}"
    labels = { "restart" => "Restarting", "stop" => "Stopping", "start" => "Starting" }

    ActionCable.server.broadcast(channel, {
      type: "log_message",
      message: "#{labels[operation] || operation.capitalize} #{deployment.name}..."
    })

    service = KamalCommandService.new(deployment.kamal_configuration, broadcast_channel: channel)
    result = service.public_send(operation)

    if result[:success]
      ActionCable.server.broadcast(channel, { type: "completed", success: true, message: "#{operation.capitalize} completed." })
    else
      ActionCable.server.broadcast(channel, { type: "completed", success: false, message: result[:error] || "#{operation.capitalize} failed" })
    end
  rescue StandardError => e
    Rails.logger.error "[KamalAppLifecycleJob] Exception (#{operation}): #{e.message}"
    ActionCable.server.broadcast("deployment_logs_#{deployment.uuid}", { type: "completed", success: false, message: e.message })
  end
end
