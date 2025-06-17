class CommandExecutionChannel < ApplicationCable::Channel
  def subscribed
    deployment_uuid = params[:deployment_uuid]
    
    if deployment_uuid.present?
      # Verify the user has access to this deployment
      deployment = current_user.deployments.find_by(uuid: deployment_uuid)
      
      if deployment
        stream_from "command_execution_#{deployment_uuid}"
        Rails.logger.info "[CommandExecutionChannel] User #{current_user.id} subscribed to command execution for deployment #{deployment_uuid}"
      else
        Rails.logger.warn "[CommandExecutionChannel] User #{current_user.id} attempted to subscribe to unauthorized deployment #{deployment_uuid}"
        reject
      end
    else
      Rails.logger.warn "[CommandExecutionChannel] Subscription rejected: missing deployment_uuid"
      reject
    end
  end

  def unsubscribed
    Rails.logger.info "[CommandExecutionChannel] User #{current_user&.id} unsubscribed from command execution channel"
  end
end