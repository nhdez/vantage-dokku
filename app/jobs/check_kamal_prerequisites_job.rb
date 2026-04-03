class CheckKamalPrerequisitesJob < ApplicationJob
  queue_as :default

  def perform(server)
    Rails.logger.info "Checking Kamal prerequisites for server: #{server.display_name}"

    service = SshConnectionService.new(server)

    docker_result = service.check_docker_installed
    if docker_result[:success]
      server.update!(
        docker_version: docker_result[:version],
        docker_checked_at: Time.current
      )
      Rails.logger.info "Docker #{docker_result[:version]} detected on #{server.display_name}"
    else
      server.update!(
        docker_version: nil,
        docker_checked_at: Time.current
      )
      Rails.logger.info "Docker not detected on #{server.display_name}: #{docker_result[:error]}"
    end

    ActionCable.server.broadcast("server_kamal_prerequisites_#{server.uuid}", {
      type: "completed",
      docker_installed: docker_result[:success],
      docker_version: docker_result[:version],
      error: docker_result[:error]
    })
  rescue StandardError => e
    Rails.logger.error "Exception checking Kamal prerequisites for server #{server.id}: #{e.message}"
    ActionCable.server.broadcast("server_kamal_prerequisites_#{server.uuid}", {
      type: "error",
      error: e.message
    })
  end
end
