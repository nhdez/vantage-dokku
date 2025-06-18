class ServerLogsChannel < ApplicationCable::Channel
  def subscribed
    deployment_uuid = params[:deployment_uuid]
    
    if deployment_uuid.present?
      # Verify the user has access to this deployment
      deployment = current_user.deployments.find_by(uuid: deployment_uuid)
      
      if deployment
        stream_from "server_logs_#{deployment_uuid}"
        Rails.logger.info "[ServerLogsChannel] User #{current_user.id} subscribed to server logs for deployment #{deployment_uuid}"
      else
        Rails.logger.warn "[ServerLogsChannel] User #{current_user.id} attempted to subscribe to unauthorized deployment #{deployment_uuid}"
        reject
      end
    else
      Rails.logger.warn "[ServerLogsChannel] Subscription rejected: missing deployment_uuid"
      reject
    end
  end

  def unsubscribed
    Rails.logger.info "[ServerLogsChannel] User #{current_user&.id} unsubscribed from server logs channel"
    
    # Optionally signal to stop log streaming when user disconnects
    # This could be enhanced to track active subscribers and stop streaming when no one is watching
  end
end