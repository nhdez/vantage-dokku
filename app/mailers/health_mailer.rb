class HealthMailer < ApplicationMailer
  def application_down_notification(deployment, health_result)
    @deployment = deployment
    @health_result = health_result
    @user = deployment.user
    @server = deployment.server
    
    @status_message = case health_result[:status]
    when 'unhealthy'
      "is experiencing issues"
    when 'timeout'
      "is not responding"
    when 'error'
      "encountered an error"
    else
      "is having problems"
    end
    
    @dashboard_url = dashboard_url
    @deployment_url = deployment_url(deployment)
    
    mail(
      to: @user.email,
      subject: "🚨 Application Alert: #{@deployment.name} #{@status_message}"
    )
  end
end
