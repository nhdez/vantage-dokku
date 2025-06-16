class DeploymentJob < ApplicationJob
  queue_as :default

  def perform(deployment)
    @deployment = deployment
    
    begin
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
          last_deployment_at: Time.current,
          deployment_logs: (existing_logs + result[:logs]).join("\n")
        )
        log_message("Deployment completed successfully")
      else
        @deployment.update!(
          deployment_status: 'failed',
          deployment_logs: (existing_logs + result[:logs]).join("\n")
        )
        log_message("Deployment failed: #{result[:error]}")
      end
      
    rescue StandardError => e
      Rails.logger.error "Deployment job failed: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      
      @deployment.update!(
        deployment_status: 'failed',
        deployment_logs: existing_logs.join("\n") + "\nERROR: #{e.message}"
      )
      log_message("Deployment failed with error: #{e.message}")
    end
  end

  private

  def log_message(message)
    timestamp = Time.current.strftime("%Y-%m-%d %H:%M:%S")
    Rails.logger.info "[DeploymentJob] [#{@deployment.uuid}] #{message}"
    
    # Append to deployment logs
    current_logs = @deployment.deployment_logs || ""
    updated_logs = current_logs + "\n[#{timestamp}] #{message}"
    @deployment.update_column(:deployment_logs, updated_logs)
  end

  def existing_logs
    (@deployment.deployment_logs || "").split("\n")
  end
end
