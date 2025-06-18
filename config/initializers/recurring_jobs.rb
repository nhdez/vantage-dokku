# Recurring job configuration for health monitoring
# This will set up regular health checks for all applications

Rails.application.configure do
  # Schedule health checks every 5 minutes
  config.after_initialize do
    # Skip during asset precompilation, rake tasks, or when database is not available
    next if defined?(Rails::Console) || Rails.env.test? || $PROGRAM_NAME.include?('rake')
    next if ENV['SKIP_HEALTH_MONITORING'] == 'true' || ENV['PRECOMPILING_ASSETS'] == '1'
    
    # Check if we can connect to the database before scheduling jobs
    begin
      ActiveRecord::Base.connection.execute('SELECT 1')
    rescue => e
      Rails.logger.info "Skipping health monitoring setup - database not available: #{e.message}"
      next
    end
    
    if defined?(SolidQueue) && Rails.env.production?
      # In production, we'll use solid_queue's recurring job feature
      # For now, we'll create a simple mechanism to schedule the health check job
      
      begin
        # Schedule initial health check
        ApplicationHealthCheckJob.set(wait: 1.minute).perform_later
        Rails.logger.info "Scheduled initial health monitoring job"
      rescue => e
        Rails.logger.error "Failed to schedule health monitoring job: #{e.message}"
      end
    elsif Rails.env.development?
      # In development, always enable health checks
      begin
        ApplicationHealthCheckJob.set(wait: 1.minute).perform_later
        Rails.logger.info "Scheduled initial health monitoring job (development)"
      rescue => e
        Rails.logger.error "Failed to schedule health monitoring job: #{e.message}"
      end
    end
  end
end