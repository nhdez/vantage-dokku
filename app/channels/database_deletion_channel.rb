class DatabaseDeletionChannel < ApplicationCable::Channel
  def subscribed
    deployment_uuid = params[:deployment_uuid]

    if deployment_uuid.present?
      # Verify the user has access to this deployment
      deployment = current_user.deployments.find_by(uuid: deployment_uuid)

      if deployment
        stream_from "database_deletion_#{deployment_uuid}"
        Rails.logger.info "[DatabaseDeletionChannel] User #{current_user.id} subscribed to database deletion updates for deployment #{deployment_uuid}"
      else
        Rails.logger.warn "[DatabaseDeletionChannel] User #{current_user.id} attempted to subscribe to unauthorized deployment #{deployment_uuid}"
        reject
      end
    else
      Rails.logger.warn "[DatabaseDeletionChannel] Subscription rejected: missing deployment_uuid"
      reject
    end
  end

  def unsubscribed
    Rails.logger.info "[DatabaseDeletionChannel] User #{current_user&.id} unsubscribed from database deletion channel"
  end
end
