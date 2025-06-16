class DeploymentLogsChannel < ApplicationCable::Channel
  def subscribed
    deployment_uuid = params[:deployment_uuid]
    attempt_id = params[:attempt_id]
    
    if deployment_uuid.present?
      # Subscribe to all logs for a deployment
      stream_from "deployment_logs_#{deployment_uuid}"
    end
    
    if attempt_id.present?
      # Subscribe to logs for a specific attempt
      stream_from "deployment_attempt_logs_#{attempt_id}"
    end
    
    Rails.logger.info "DeploymentLogsChannel: Subscribed to deployment #{deployment_uuid}, attempt #{attempt_id}"
  end

  def unsubscribed
    Rails.logger.info "DeploymentLogsChannel: Unsubscribed"
  end
end