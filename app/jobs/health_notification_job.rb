class HealthNotificationJob < ApplicationJob
  queue_as :notifications
  
  retry_on StandardError, wait: 5.minutes, attempts: 3
  
  def perform(deployment_id, health_result)
    deployment = Deployment.find(deployment_id)
    
    Rails.logger.info "Sending health notification for #{deployment.name} (status: #{health_result[:status]})"
    
    # Send email to the deployment owner
    HealthMailer.application_down_notification(deployment, health_result).deliver_now
    
    # Log the notification
    ActivityLog.create!(
      user: deployment.user,
      controller_name: 'health_monitoring',
      action: 'notification_sent',
      occurred_at: Time.current,
      details: "Health notification sent for #{deployment.name} - Status: #{health_result[:status]}"
    )
    
  rescue StandardError => e
    Rails.logger.error "Failed to send health notification for deployment #{deployment_id}: #{e.message}"
    raise e
  end
end
