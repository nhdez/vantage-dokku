class DashboardController < ApplicationController
  def index
    @user_deployments = current_user.deployments
                                   .includes(:server, :application_healths)
                                   .recent
    
    @total_deployments = @user_deployments.count
    @connected_servers = current_user.servers.where(connection_status: 'connected').count
    @total_servers = current_user.servers.count
    
    # Health monitoring statistics
    @monitored_deployments = @user_deployments
                               .joins(:server)
                               .where(servers: { connection_status: 'connected' })
                               .select { |deployment| deployment.dokku_url.present? }
    
    @healthy_deployments = @monitored_deployments.select(&:is_healthy?).count
    @unhealthy_deployments = @monitored_deployments.select(&:is_unhealthy?).count
    @unknown_deployments = @monitored_deployments.count - @healthy_deployments - @unhealthy_deployments
    
    # Calculate overall uptime percentage
    if @monitored_deployments.any?
      @overall_uptime = ((@healthy_deployments.to_f / @monitored_deployments.count) * 100).round(1)
    else
      @overall_uptime = 0
    end
    
    # Recent activity
    @recent_activity = ActivityLog.where(user: current_user)
                                 .order(occurred_at: :desc)
                                 .limit(5)
    
    # Get deployments with their health status for the status grid
    @deployment_health_status = @monitored_deployments.map do |deployment|
      {
        deployment: deployment,
        health_checks: deployment.last_20_health_checks.includes(:deployment),
        current_status: deployment.current_health_status,
        uptime_percentage: deployment.health_uptime_percentage
      }
    end
  end

  def settings
    # Settings will be handled by Devise user registration controller
    redirect_to edit_user_registration_path
  end

  private

end
