class KamalRollbackJob < ApplicationJob
  queue_as :default

  def perform(deployment, version, deployment_attempt)
    channel = "deployment_logs_#{deployment.uuid}"

    deployment.update!(deployment_status: "deploying")
    deployment_attempt.update!(status: "running", started_at: Time.current)

    ActionCable.server.broadcast(channel, { type: "log_message", message: "Rolling back #{deployment.name} to version #{version}..." })

    service = KamalCommandService.new(deployment.kamal_configuration, broadcast_channel: channel)
    result = service.rollback(version)

    if result[:success]
      deployment.update!(deployment_status: "deployed", last_deployment_at: Time.current)
      deployment_attempt.update!(status: "success", completed_at: Time.current, logs: result[:output].join("\n"))
      ActionCable.server.broadcast(channel, { type: "completed", success: true, message: "Rollback to #{version} completed!" })
    else
      deployment.update!(deployment_status: "failed")
      deployment_attempt.update!(status: "failed", completed_at: Time.current,
                                  logs: result[:output].join("\n"), error_message: result[:error])
      ActionCable.server.broadcast(channel, { type: "completed", success: false, message: result[:error] || "Rollback failed" })
    end
  rescue StandardError => e
    Rails.logger.error "[KamalRollbackJob] Exception: #{e.message}"
    deployment.update!(deployment_status: "failed") rescue nil
    deployment_attempt.update!(status: "failed", completed_at: Time.current, error_message: e.message) rescue nil
  end
end
