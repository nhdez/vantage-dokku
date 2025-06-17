class DeploymentJob < ApplicationJob
  queue_as :default

  def perform(deployment)
    @deployment = deployment
    
    begin
      # Update status to deploying at the start
      @deployment.update!(deployment_status: 'deploying')
      log_message("Starting deployment for #{@deployment.name}")
      
      # Initialize deployment service
      service = DeploymentService.new(@deployment)
      
      # Execute deployment based on method
      case @deployment.deployment_method
      when 'github_repo', 'public_repo'
        result = service.deploy_from_repository
      else
        raise "Unsupported deployment method: #{@deployment.deployment_method}"
      end
      
      if result[:success]
        @deployment.update!(
          deployment_status: 'deployed',
          last_deployment_at: Time.current
        )
        log_message("Deployment completed successfully!")
        log_message("Your application is now live and running on Dokku.")
      else
        @deployment.update!(deployment_status: 'failed')
        log_message("Deployment failed: #{result[:error]}")
        log_message("Please check the logs above for more details.")
      end
      
    rescue Net::SSH::AuthenticationFailed => e
      Rails.logger.error "SSH Authentication failed: #{e.message}"
      @deployment.update!(deployment_status: 'failed')
      log_message("ERROR: SSH Authentication failed - Please check your server credentials")
      
    rescue Net::SSH::ConnectionTimeout => e
      Rails.logger.error "SSH Connection timeout: #{e.message}"
      @deployment.update!(deployment_status: 'failed')
      log_message("ERROR: Connection timeout - Server may be unreachable")
      
    rescue StandardError => e
      Rails.logger.error "Deployment job failed: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      
      @deployment.update!(deployment_status: 'failed')
      log_message("ERROR: Deployment failed - #{e.message}")
      log_message("Please contact support if this issue persists.")
    end
  end

  private

  def log_message(message)
    timestamp = Time.current.strftime("%H:%M:%S")
    formatted_message = "[#{timestamp}] #{message}"
    Rails.logger.info "[DeploymentJob] [#{@deployment.uuid}] #{message}"
    
    # Update deployment logs in database
    current_logs = @deployment.deployment_logs || ""
    updated_logs = current_logs + "\n#{formatted_message}"
    @deployment.update_column(:deployment_logs, updated_logs)
  end
end
