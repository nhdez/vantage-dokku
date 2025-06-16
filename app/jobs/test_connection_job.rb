class TestConnectionJob < ApplicationJob
  queue_as :default

  def perform(server_id, user_id)
    @server = Server.find(server_id)
    @user = User.find(user_id)
    
    begin
      service = SshConnectionService.new(@server)
      result = service.test_connection_and_gather_info
      
      if result[:success]
        # Server info was already updated by the service
        ActionCable.server.broadcast("test_connection_#{@server.uuid}", {
          success: true,
          message: "Connection successful! Server information has been updated.",
          server_info: result[:server_info],
          connection_status: @server.reload.connection_status,
          server_data: {
            os_version: @server.os_version,
            cpu_model: @server.cpu_model,
            cpu_cores: @server.cpu_cores,
            ram_total: @server.formatted_ram,
            disk_total: @server.formatted_disk,
            dokku_version: @server.formatted_dokku_version,
            dokku_installed: @server.dokku_installed?,
            last_connected_at: @server.last_connected_at&.strftime("%B %d, %Y at %I:%M %p"),
            last_connected_ago: @server.last_connected_ago
          }
        })
      else
        ActionCable.server.broadcast("test_connection_#{@server.uuid}", {
          success: false,
          message: result[:error],
          connection_status: @server.reload.connection_status
        })
      end
      
    rescue StandardError => e
      Rails.logger.error "Background connection test failed: #{e.message}"
      @server.update!(connection_status: 'failed')
      
      ActionCable.server.broadcast("test_connection_#{@server.uuid}", {
        success: false,
        message: "An unexpected error occurred: #{e.message}",
        connection_status: 'failed'
      })
    end
  end
end