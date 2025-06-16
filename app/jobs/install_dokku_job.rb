class InstallDokkuJob < ApplicationJob
  queue_as :default

  def perform(server_id, user_id)
    @server = Server.find(server_id)
    @user = User.find(user_id)
    
    begin
      service = SshConnectionService.new(@server)
      result = service.install_dokku_with_key_setup
      
      if result[:success]
        ActionCable.server.broadcast("install_dokku_#{@server.uuid}", {
          success: true,
          message: "Dokku installation completed successfully!",
          output: result[:output],
          dokku_installed: result[:dokku_installed],
          server_data: {
            dokku_version: @server.reload.formatted_dokku_version,
            dokku_installed: @server.dokku_installed?
          }
        })
      else
        ActionCable.server.broadcast("install_dokku_#{@server.uuid}", {
          success: false,
          message: result[:error],
          output: result[:output] || ""
        })
      end
      
    rescue StandardError => e
      Rails.logger.error "Background Dokku installation failed: #{e.message}"
      
      ActionCable.server.broadcast("install_dokku_#{@server.uuid}", {
        success: false,
        message: "An unexpected error occurred: #{e.message}",
        output: ""
      })
    end
  end
end