class InstallDokkuJob < ApplicationJob
  queue_as :default

  def perform(server_id, user_id)
    @server = Server.find(server_id)
    @user = User.find(user_id)

    broadcast("install_dokku_#{@server.uuid}", type: "started",
              message: "Starting Dokku installation on #{@server.name}...")

    begin
      service = SshConnectionService.new(@server)
      result = service.install_dokku_with_key_setup

      if result[:success]
        result[:output].to_s.each_line do |line|
          broadcast("install_dokku_#{@server.uuid}", type: "output", message: line.chomp) if line.strip.present?
        end

        broadcast("install_dokku_#{@server.uuid}",
          type: "completed", success: true,
          message: "Dokku installation completed successfully!",
          dokku_installed: result[:dokku_installed],
          server_data: {
            dokku_version: @server.reload.formatted_dokku_version,
            dokku_installed: @server.dokku_installed?
          })
      else
        broadcast("install_dokku_#{@server.uuid}",
          type: "completed", success: false,
          message: result[:error], output: result[:output] || "")
      end

    rescue StandardError => e
      Rails.logger.error "Background Dokku installation failed: #{e.message}"
      broadcast("install_dokku_#{@server.uuid}",
        type: "completed", success: false,
        message: "An unexpected error occurred: #{e.message}")
    end
  end

  private

  def broadcast(channel, payload)
    ActionCable.server.broadcast(channel, payload)
  end
end
