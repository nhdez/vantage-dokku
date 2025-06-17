class DeploymentJob < ApplicationJob
  queue_as :default

  def perform(deployment)
    @deployment = deployment
    
    begin
      # Update status to deploying at the start
      @deployment.update!(deployment_status: 'deploying')
      
      # Initialize deployment service (this will create a new deployment attempt)
      service = DeploymentService.new(@deployment)
      
      # Execute deployment based on method
      case @deployment.deployment_method
      when 'github_repo', 'public_repo'
        result = service.deploy_from_repository
      else
        raise "Unsupported deployment method: #{@deployment.deployment_method}"
      end
      
      # Update deployment status based on the actual result from the deployment attempt
      latest_attempt = @deployment.latest_deployment_attempt
      
      if result[:success] && latest_attempt&.success?
        @deployment.update!(
          deployment_status: 'deployed',
          last_deployment_at: Time.current
        )
        Rails.logger.info "Deployment #{@deployment.uuid} completed successfully (Attempt ##{latest_attempt.attempt_number})"
      else
        @deployment.update!(deployment_status: 'failed')
        error_msg = latest_attempt&.error_message || result[:error] || "Unknown error"
        Rails.logger.error "Deployment #{@deployment.uuid} failed (Attempt ##{latest_attempt&.attempt_number || 'unknown'}): #{error_msg}"
      end
      
    rescue Net::SSH::AuthenticationFailed => e
      Rails.logger.error "SSH Authentication failed: #{e.message}"
      @deployment.update!(deployment_status: 'failed')
      
    rescue Net::SSH::ConnectionTimeout => e
      Rails.logger.error "SSH Connection timeout: #{e.message}"
      @deployment.update!(deployment_status: 'failed')
      
    rescue StandardError => e
      Rails.logger.error "Deployment job failed: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      
      @deployment.update!(deployment_status: 'failed')
      
      # If we have a deployment attempt, mark it as failed
      latest_attempt = @deployment.latest_deployment_attempt
      if latest_attempt && !latest_attempt.completed?
        latest_attempt.update!(
          status: 'failed',
          completed_at: Time.current,
          error_message: e.message
        )
      end
    end
  end
end
