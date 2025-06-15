class CreateDokkuAppJob < ApplicationJob
  queue_as :default

  def perform(deployment)
    Rails.logger.info "Creating Dokku app for deployment: #{deployment.display_name}"
    
    begin
      service = SshConnectionService.new(deployment.server)
      result = service.create_dokku_app(deployment.dokku_app_name)
      
      if result[:success]
        Rails.logger.info "Successfully created Dokku app '#{deployment.dokku_app_name}' for deployment: #{deployment.display_name}"
        
        # Create activity log entry
        ActivityLog.create!(
          user: deployment.user,
          action: 'dokku_app_auto_created',
          details: "Automatically created Dokku app: #{deployment.dokku_app_name} for deployment: #{deployment.display_name}",
          ip_address: '127.0.0.1' # System-generated
        )
      else
        Rails.logger.error "Failed to create Dokku app '#{deployment.dokku_app_name}' for deployment: #{deployment.display_name} - #{result[:error]}"
        
        # Create activity log entry for failure
        ActivityLog.create!(
          user: deployment.user,
          action: 'dokku_app_auto_creation_failed',
          details: "Failed to automatically create Dokku app: #{deployment.dokku_app_name} - #{result[:error]}",
          ip_address: '127.0.0.1' # System-generated
        )
      end
    rescue StandardError => e
      Rails.logger.error "Exception creating Dokku app for deployment #{deployment.id}: #{e.message}"
      
      # Create activity log entry for exception
      ActivityLog.create!(
        user: deployment.user,
        action: 'dokku_app_auto_creation_failed',
        details: "Exception creating Dokku app: #{deployment.dokku_app_name} - #{e.message}",
        ip_address: '127.0.0.1' # System-generated
      )
    end
  end
end
