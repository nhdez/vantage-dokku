class KamalDeploymentJob < ApplicationJob
  queue_as :default

  def perform(deployment, deployment_attempt)
    channel = "deployment_logs_#{deployment.uuid}"

    deployment.update!(deployment_status: "deploying")
    deployment_attempt.update!(status: "running", started_at: Time.current)

    ActionCable.server.broadcast(channel, { type: "log_message", message: "Starting Kamal deployment for #{deployment.name}..." })
    ActionCable.server.broadcast(channel, { type: "log_message", message: "Image: #{deployment.kamal_configuration.image}" })

    service = KamalCommandService.new(deployment.kamal_configuration, broadcast_channel: channel)
    result = service.deploy

    if result[:success]
      deployment.update!(deployment_status: "deployed", last_deployment_at: Time.current)
      deployment_attempt.update!(status: "success", completed_at: Time.current, logs: result[:output].join("\n"))
      ActionCable.server.broadcast(channel, { type: "completed", success: true, message: "Deployment completed successfully!" })
      Rails.logger.info "[KamalDeploymentJob] Deployment #{deployment.uuid} succeeded"
    else
      deployment.update!(deployment_status: "failed")
      deployment_attempt.update!(status: "failed", completed_at: Time.current,
                                  logs: result[:output].join("\n"), error_message: result[:error])
      ActionCable.server.broadcast(channel, { type: "completed", success: false, message: result[:error] || "Deployment failed" })
      Rails.logger.error "[KamalDeploymentJob] Deployment #{deployment.uuid} failed: #{result[:error]}"
    end
  rescue StandardError => e
    Rails.logger.error "[KamalDeploymentJob] Exception for #{deployment.uuid}: #{e.message}"
    deployment.update!(deployment_status: "failed") rescue nil
    deployment_attempt.update!(status: "failed", completed_at: Time.current, error_message: e.message) rescue nil
    ActionCable.server.broadcast("deployment_logs_#{deployment.uuid}", { type: "completed", success: false, message: e.message })
  end
end
