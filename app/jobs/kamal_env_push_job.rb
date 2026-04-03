class KamalEnvPushJob < ApplicationJob
  queue_as :default

  def perform(deployment)
    kamal_config = deployment.kamal_configuration
    channel = "update_environment_#{deployment.uuid}"

    unless kamal_config
      ActionCable.server.broadcast(channel, { type: "error", message: "Kamal configuration not found" })
      return
    end

    ActionCable.server.broadcast(channel, { type: "started", message: "Pushing environment variables to Kamal servers..." })

    service = KamalCommandService.new(kamal_config, broadcast_channel: channel)
    result = service.env_push

    if result[:success]
      Rails.logger.info "[KamalEnvPushJob] Env push successful for deployment #{deployment.uuid}"
      ActionCable.server.broadcast(channel, { type: "completed", success: true, message: "Environment variables pushed successfully." })
    else
      error_msg = result[:error] || "Env push failed"
      kamal_config.update!(error_message: error_msg)
      Rails.logger.error "[KamalEnvPushJob] Env push failed for deployment #{deployment.uuid}: #{error_msg}"
      ActionCable.server.broadcast(channel, { type: "completed", success: false, message: error_msg })
    end
  rescue StandardError => e
    Rails.logger.error "[KamalEnvPushJob] Exception for deployment #{deployment.uuid}: #{e.message}"
    ActionCable.server.broadcast("update_environment_#{deployment.uuid}", { type: "error", message: e.message })
  end
end
