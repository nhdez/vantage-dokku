class KamalSetupJob < ApplicationJob
  queue_as :default

  def perform(deployment)
    channel = "kamal_setup_#{deployment.uuid}"
    config = deployment.kamal_configuration

    ActionCable.server.broadcast(channel, { type: "started", message: "Running kamal setup — this may take a few minutes..." })

    service = KamalCommandService.new(config, broadcast_channel: channel)
    result = service.setup

    if result[:success]
      config.update!(configured: true, error_message: nil)

      # Mark all assigned servers as Docker-ready by triggering a prerequisites check
      config.kamal_servers.includes(:server).each do |ks|
        CheckKamalPrerequisitesJob.perform_later(ks.server)
      end

      ActionCable.server.broadcast(channel, { type: "completed", success: true, message: "Setup completed successfully! Servers are ready." })
      Rails.logger.info "[KamalSetupJob] Setup succeeded for deployment #{deployment.uuid}"
    else
      config.update!(error_message: result[:error])
      ActionCable.server.broadcast(channel, { type: "completed", success: false, message: result[:error] || "Setup failed" })
      Rails.logger.error "[KamalSetupJob] Setup failed for deployment #{deployment.uuid}: #{result[:error]}"
    end
  rescue StandardError => e
    Rails.logger.error "[KamalSetupJob] Exception for deployment #{deployment.uuid}: #{e.message}"
    deployment.kamal_configuration&.update!(error_message: e.message) rescue nil
    ActionCable.server.broadcast("kamal_setup_#{deployment.uuid}", { type: "completed", success: false, message: e.message })
  end
end
