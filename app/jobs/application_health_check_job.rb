class ApplicationHealthCheckJob < ApplicationJob
  queue_as :health_monitoring
  
  retry_on StandardError, wait: 1.minute, attempts: 3
  
  def perform(deployment_id = nil)
    if deployment_id
      # Check specific deployment
      deployment = Deployment.find_by(id: deployment_id)
      if deployment
        Rails.logger.info "Running health check for deployment: #{deployment.name}"
        result = ApplicationHealthService.check_deployment(deployment)
        send_notification_if_needed(deployment, result)
      end
    else
      # Check all deployments
      Rails.logger.info "Running health checks for all deployments"
      checked_count = 0
      
      Deployment.joins(:server)
                .where(servers: { connection_status: 'connected' })
                .includes(:server, :domains)
                .find_each do |deployment|
        next unless deployment.dokku_url.present?
        begin
          result = ApplicationHealthService.check_deployment(deployment)
          send_notification_if_needed(deployment, result)
          checked_count += 1
        rescue StandardError => e
          Rails.logger.error "Health check failed for #{deployment.name}: #{e.message}"
        end
      end
      
      Rails.logger.info "Completed health checks for #{checked_count} deployments"
      
      # Schedule the next health check run in 5 minutes (for recurring monitoring)
      if Rails.env.production? || ENV['ENABLE_RECURRING_HEALTH_CHECKS'] == 'true'
        ApplicationHealthCheckJob.set(wait: 5.minutes).perform_later
        Rails.logger.info "Scheduled next health check run in 5 minutes"
      end
    end
  end
  
  private
  
  def send_notification_if_needed(deployment, result)
    # Only send notification if the app is unhealthy and meets notification criteria
    if result[:status] != 'healthy' && deployment.needs_health_notification?
      HealthNotificationJob.perform_later(deployment.id, result)
    end
  end
end
