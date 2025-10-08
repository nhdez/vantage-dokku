class DeploymentDeletionChannel < ApplicationCable::Channel
  def subscribed
    user_id = params[:user_id]

    if user_id.present? && user_id.to_s == current_user.id.to_s
      stream_from "deployment_deletion_#{user_id}"
      Rails.logger.info "[DeploymentDeletionChannel] User #{current_user.id} subscribed to deployment deletion updates"
    else
      Rails.logger.warn "[DeploymentDeletionChannel] Subscription rejected: invalid user_id"
      reject
    end
  end

  def unsubscribed
    Rails.logger.info "[DeploymentDeletionChannel] User #{current_user&.id} unsubscribed from deployment deletion channel"
  end
end