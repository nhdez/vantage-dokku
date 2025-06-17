class UpdateServerJob < ApplicationJob
  queue_as :default

  def perform(server_id, user_id)
    @server = Server.find(server_id)
    @user = User.find(user_id)
    
    begin
      service = SshConnectionService.new(@server)
      result = service.update_server_packages
      
      if result[:success]
        # Check if reboot is required
        reboot_required = result[:output]&.include?('REBOOT_REQUIRED') || false
        
        ActionCable.server.broadcast("update_server_#{@server.uuid}", {
          success: true,
          message: reboot_required ? 
            "Server updated successfully! A reboot is required to complete some updates." : 
            "Server updated successfully! All packages are up to date.",
          output: result[:output],
          reboot_required: reboot_required
        })
      else
        ActionCable.server.broadcast("update_server_#{@server.uuid}", {
          success: false,
          message: result[:error],
          output: result[:output] || ""
        })
      end
      
    rescue StandardError => e
      Rails.logger.error "Background server update failed: #{e.message}"
      
      ActionCable.server.broadcast("update_server_#{@server.uuid}", {
        success: false,
        message: "An unexpected error occurred: #{e.message}",
        output: ""
      })
    end
  end
end