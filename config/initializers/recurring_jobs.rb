# Recurring job configuration for health monitoring
# This will set up regular health checks for all applications

Rails.application.configure do
  # Schedule health checks every 5 minutes
  config.after_initialize do
    if defined?(SolidQueue) && Rails.env.production?
      # In production, we'll use solid_queue's recurring job feature
      # For now, we'll create a simple mechanism to schedule the health check job
      
      # Schedule initial health check
      ApplicationHealthCheckJob.set(wait: 1.minute).perform_later
      
      Rails.logger.info "Scheduled initial health monitoring job"
    end
  end
end

# For development, we can manually trigger health checks or use a simpler approach