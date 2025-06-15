namespace :health do
  desc "Run health checks for all deployments"
  task check_all: :environment do
    puts "Starting health checks for all deployments..."
    
    start_time = Time.current
    ApplicationHealthCheckJob.perform_now
    end_time = Time.current
    
    puts "Health checks completed in #{(end_time - start_time).round(2)} seconds"
  end
  
  desc "Run health check for a specific deployment"
  task :check, [:deployment_id] => :environment do |t, args|
    deployment_id = args[:deployment_id]
    
    if deployment_id.blank?
      puts "Usage: rails health:check[deployment_id]"
      exit 1
    end
    
    deployment = Deployment.find_by(id: deployment_id)
    unless deployment
      puts "Deployment with ID #{deployment_id} not found"
      exit 1
    end
    
    puts "Running health check for deployment: #{deployment.name}"
    result = ApplicationHealthService.check_deployment(deployment)
    puts "Result: #{result[:status]} (#{result[:response_code]}) #{result[:response_time]}ms"
  end
  
  desc "Setup recurring health monitoring (every 5 minutes)"
  task setup_recurring: :environment do
    puts "Setting up recurring health monitoring..."
    
    # Cancel any existing recurring health check jobs
    # Note: This is a simplified approach. In production, you might want to use
    # a more sophisticated job scheduler like sidekiq-cron or good_job
    
    # Schedule the first job, which will then schedule the next one
    ApplicationHealthCheckJob.set(wait: 5.minutes).perform_later
    
    puts "Recurring health monitoring setup completed"
    puts "Health checks will run every 5 minutes"
  end
  
  desc "Show health statistics"
  task stats: :environment do
    puts "\n=== Health Monitoring Statistics ==="
    
    total_deployments = Deployment.count
    monitored_deployments = Deployment.joins(:server)
                                     .where(servers: { connection_status: 'connected' })
                                     .includes(:server, :domains)
                                     .select { |d| d.dokku_url.present? }
                                     .count
    
    puts "Total deployments: #{total_deployments}"
    puts "Monitored deployments: #{monitored_deployments}"
    
    if monitored_deployments > 0
      # Get health statistics
      healthy_count = 0
      unhealthy_count = 0
      unknown_count = 0
      
      Deployment.joins(:server)
                .where(servers: { connection_status: 'connected' })
                .includes(:server, :domains, :application_healths)
                .each do |deployment|
        next unless deployment.dokku_url.present?
        latest_health = deployment.latest_health_check
        if latest_health
          if latest_health.healthy?
            healthy_count += 1
          else
            unhealthy_count += 1
          end
        else
          unknown_count += 1
        end
      end
      
      puts "Healthy applications: #{healthy_count}"
      puts "Unhealthy applications: #{unhealthy_count}"
      puts "Unknown status: #{unknown_count}"
      
      if monitored_deployments > 0
        uptime_percentage = ((healthy_count.to_f / monitored_deployments) * 100).round(1)
        puts "Overall uptime: #{uptime_percentage}%"
      end
      
      # Recent health checks
      recent_checks = ApplicationHealth.where('checked_at > ?', 1.hour.ago).count
      puts "Health checks in last hour: #{recent_checks}"
    end
    
    puts "\n=== Recent Health Check Activity ==="
    ApplicationHealth.includes(:deployment)
                    .recent
                    .limit(5)
                    .each do |health|
      puts "#{health.deployment.name}: #{health.status} (#{health.checked_at.strftime('%H:%M:%S')})"
    end
  end
  
  desc "Cleanup old health check records (keeps last 20 per deployment)"
  task cleanup: :environment do
    puts "Cleaning up old health check records..."
    
    total_cleaned = 0
    Deployment.includes(:application_healths).each do |deployment|
      old_checks = deployment.application_healths
                            .order(checked_at: :desc)
                            .offset(20)
      
      if old_checks.any?
        count = old_checks.count
        old_checks.delete_all
        total_cleaned += count
        puts "Cleaned #{count} old records for #{deployment.name}"
      end
    end
    
    puts "Cleanup completed. Removed #{total_cleaned} old health check records."
  end
end